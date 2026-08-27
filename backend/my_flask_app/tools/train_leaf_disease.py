#!/usr/bin/env python
"""Fine-tune the leaf-disease CNN that ``/api/disease/identify`` serves.

Produces exactly the two files ``app/ai/model_loader.py`` loads at runtime, so
training and serving cannot drift apart:

    python tools/train_leaf_disease.py --data datasets/leaf_disease
    -> models/leaf_disease.pt              TorchScript module
       models/leaf_disease_labels.txt      one class per line, in class order
       models/leaf_disease_report.json     accuracy, per-class recall, field split

Then point the backend at them and restart:

    AI_DISEASE_MODEL_PATH=/abs/path/models/leaf_disease.pt
    AI_DISEASE_LABELS_PATH=/abs/path/models/leaf_disease_labels.txt

Build the dataset first with ``tools/build_leaf_dataset.py``, which merges
PlantVillage and PlantDoc into the ``ImageFolder`` layout this reads.

Written for a CPU box
---------------------
This project's dev machine has no CUDA, so the defaults are chosen to finish a
useful run in ~2 hours on four cores rather than to win a benchmark:

  * **MobileNetV3-Large** at **192px** — roughly an order of magnitude cheaper
    per image than ResNet-18 at 224 for a couple of points of accuracy, and it
    is the backbone that can later run on the drone's companion computer.
  * ``--max-minutes`` stops cleanly on a wall-clock budget instead of leaving
    you to guess an epoch count.
  * Every epoch writes ``models/leaf_disease.ckpt``, and ``--resume`` picks it
    up, so an interrupted run is not a lost afternoon.
  * The TorchScript export happens on every validation improvement, so there is
    always a servable model on disk even if the run is killed mid-way.

The number to read
------------------
The headline accuracy is not the interesting one. PlantVillage's images are
detached leaves on a uniform grey sheet and a model scores ~99% on them while
being useless on a phone photo of a plant in the ground. The report therefore
scores ``field`` images (PlantDoc, real backgrounds) separately from ``lab``
ones, and **field accuracy is what predicts how the app behaves**. Per-class
recall matters for the same reason the crop trainer weights its loss: a model
that answers "healthy" to everything can still look respectable on averages.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import random
import sys
import time
from collections import Counter, defaultdict

try:
    import torch
    from torch import nn
    from torch.utils.data import DataLoader, Dataset
    from torchvision import datasets, models, transforms
except ImportError:  # pragma: no cover - the tool is optional
    sys.exit(
        "This trainer needs PyTorch. Install it first:\n"
        "    pip install torch torchvision\n"
        "(The backend itself does not need torch — /api/disease falls back to "
        "the OpenCV heuristic when no model is configured.)"
    )


ARCHITECTURES = {
    "mobilenet_v3_large": (models.mobilenet_v3_large, models.MobileNet_V3_Large_Weights.DEFAULT),
    "mobilenet_v3_small": (models.mobilenet_v3_small, models.MobileNet_V3_Small_Weights.DEFAULT),
    "resnet18": (models.resnet18, models.ResNet18_Weights.DEFAULT),
    "efficientnet_b0": (models.efficientnet_b0, models.EfficientNet_B0_Weights.DEFAULT),
}

# Must match app/ai/model_loader.py's preprocessing exactly, or the served
# model quietly loses accuracy without ever raising an error.
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]


# ── Data ──────────────────────────────────────────────────────────────────────

class TransformedSubset(Dataset):
    """A subset that owns its transform.

    ``torch.utils.data.random_split`` hands back Subsets that share one
    underlying dataset, so train and validation would share one transform —
    and validating under training augmentation measures a harder problem than
    the real one. Holding the transform here keeps the two honestly separate.
    """

    def __init__(self, base: datasets.ImageFolder, indices: list, transform):
        self.base = base
        self.indices = list(indices)
        self.transform = transform

    def __len__(self) -> int:
        return len(self.indices)

    def __getitem__(self, position):
        path, target = self.base.samples[self.indices[position]]
        image = self.base.loader(path)
        return self.transform(image), target


def build_transforms(img_size: int):
    """Augmentation aimed at what a phone camera actually produces.

    Flips and rotation because a farmer holds the phone at whatever angle;
    colour jitter because a 9 a.m. photo and a 2 p.m. photo of the same leaf
    are different images; RandomResizedCrop because the leaf may fill the frame
    or sit in the corner of it.
    """
    train = transforms.Compose([
        transforms.RandomResizedCrop(img_size, scale=(0.5, 1.0)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomVerticalFlip(),
        transforms.RandomRotation(30),
        transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.25, hue=0.04),
        transforms.ToTensor(),
        transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
    ])
    validate = transforms.Compose([
        transforms.Resize(int(img_size * 1.14)),
        transforms.CenterCrop(img_size),
        transforms.ToTensor(),
        transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
    ])
    return train, validate


def stratified_split(base: datasets.ImageFolder, val_split: float, seed: int):
    """Split per class, so every class is represented in validation.

    A global random split can leave a small class with zero validation images,
    and its recall then reads as ``null`` in the report — precisely the class
    you most wanted to check.
    """
    by_class = defaultdict(list)
    for index, (_path, target) in enumerate(base.samples):
        by_class[target].append(index)

    rng = random.Random(seed)
    train_indices, val_indices = [], []
    for target, indices in by_class.items():
        rng.shuffle(indices)
        cut = max(1, int(round(len(indices) * val_split)))
        val_indices.extend(indices[:cut])
        train_indices.extend(indices[cut:])

    rng.shuffle(train_indices)
    return train_indices, val_indices


def origin_of(path: str) -> str:
    """``field`` or ``lab`` — encoded into the filename by build_leaf_dataset."""
    return "field" if "__field__" in os.path.basename(path) else "lab"


# ── Model ─────────────────────────────────────────────────────────────────────

def build_model(arch: str, num_classes: int, freeze_until: float):
    if arch not in ARCHITECTURES:
        raise SystemExit(f"Unknown --arch '{arch}'. Choose from: {', '.join(sorted(ARCHITECTURES))}")
    factory, weights = ARCHITECTURES[arch]
    model = factory(weights=weights)

    # Swap the 1000-class ImageNet head for ours. Each torchvision family names
    # its head differently, hence the branches.
    if hasattr(model, "fc"):                        # ResNet
        model.fc = nn.Linear(model.fc.in_features, num_classes)
    elif hasattr(model, "classifier"):              # MobileNet / EfficientNet
        classifier = model.classifier
        if isinstance(classifier, nn.Sequential):
            for index in range(len(classifier) - 1, -1, -1):
                if isinstance(classifier[index], nn.Linear):
                    classifier[index] = nn.Linear(classifier[index].in_features, num_classes)
                    break
        else:
            model.classifier = nn.Linear(classifier.in_features, num_classes)
    else:  # pragma: no cover - future torchvision layouts
        raise SystemExit(f"Don't know how to replace the head of {arch}.")

    # Freezing the early layers is the main CPU lever: the first blocks learn
    # generic edge/texture filters that a leaf dataset will not improve on, and
    # skipping their gradients cuts backward cost substantially. 0.0 trains
    # everything; 1.0 trains the head only.
    if freeze_until > 0:
        parameters = list(model.parameters())
        cutoff = int(len(parameters) * min(freeze_until, 1.0))
        for parameter in parameters[:cutoff]:
            parameter.requires_grad = False

    return model


def class_weights(targets: list, num_classes: int) -> torch.Tensor:
    """Inverse-frequency weights so rare classes are not simply ignored.

    Merged public data is lopsided — PlantVillage has 5,000 healthy tomato
    leaves and PlantDoc has 60 of some diseases — and an unweighted loss will
    happily trade every rare class away for a better average.
    """
    counts = Counter(targets)
    total = len(targets)
    return torch.tensor(
        [total / (num_classes * max(1, counts.get(index, 0))) for index in range(num_classes)],
        dtype=torch.float32,
    )


# ── Evaluation ────────────────────────────────────────────────────────────────

def evaluate(model, loader, device, class_names, origins):
    """Overall/lab/field accuracy, per-class recall, and the worst confusions."""
    model.eval()
    correct = total = 0
    per_class = {name: [0, 0] for name in class_names}
    per_origin = {"lab": [0, 0], "field": [0, 0]}
    confusions: Counter = Counter()
    position = 0

    with torch.no_grad():
        for images, labels in loader:
            images, labels = images.to(device), labels.to(device)
            predictions = model(images).argmax(dim=1)

            for label, prediction in zip(labels.tolist(), predictions.tolist()):
                origin = origins[position] if position < len(origins) else "lab"
                position += 1

                hit = int(label == prediction)
                correct += hit
                total += 1
                per_class[class_names[label]][1] += 1
                per_class[class_names[label]][0] += hit
                per_origin[origin][1] += 1
                per_origin[origin][0] += hit
                if not hit:
                    confusions[(class_names[label], class_names[prediction])] += 1

    accuracy = correct / total if total else 0.0
    recalls = {
        name: (round(hit / seen, 3) if seen else None)
        for name, (hit, seen) in per_class.items()
    }
    by_origin = {
        origin: {
            "accuracy": round(hit / seen, 4) if seen else None,
            "images": seen,
        }
        for origin, (hit, seen) in per_origin.items()
    }
    worst = [
        {"true": true, "predicted": predicted, "count": count}
        for (true, predicted), count in confusions.most_common(10)
    ]
    return accuracy, recalls, by_origin, worst


# ── Export ────────────────────────────────────────────────────────────────────

def export(model, class_names, img_size, model_path, labels_path):
    """Write the TorchScript module + labels the backend loads.

    Traced on CPU regardless of the training device: the backend loads with
    ``map_location="cpu"`` and a module traced on GPU carries device-pinned
    constants that fail there.

    A **copy** is moved and traced, never the live model. ``nn.Module.to()``
    rebinds parameter data in place, so moving the training model to CPU and
    back would leave the optimiser's state tensors (``exp_avg`` and friends) on
    the old device — which raises a device-mismatch on the next step, several
    minutes into the following epoch, on GPU boxes only. Copying costs a few
    MB once per improvement and removes the whole class of problem.
    """
    cpu_model = copy.deepcopy(model).to("cpu").eval()
    example = torch.randn(1, 3, img_size, img_size)
    with torch.no_grad():
        scripted = torch.jit.trace(cpu_model, example)
        scripted = torch.jit.freeze(scripted)
    scripted.save(model_path)
    with open(labels_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(class_names) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--data", default="datasets/leaf_disease",
                        help="ImageFolder root built by tools/build_leaf_dataset.py")
    parser.add_argument("--out", default="models")
    parser.add_argument("--stem", default="leaf_disease",
                        help="output filename stem")
    parser.add_argument("--arch", default="mobilenet_v3_large", choices=sorted(ARCHITECTURES))
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=6e-4)
    parser.add_argument("--img-size", type=int, default=192)
    parser.add_argument("--val-split", type=float, default=0.15)
    parser.add_argument("--workers", type=int, default=3,
                        help="DataLoader workers; JPEG decode is the CPU bottleneck")
    parser.add_argument("--freeze-until", type=float, default=0.35,
                        help="fraction of layers to freeze (0=full fine-tune, 1=head only)")
    parser.add_argument("--max-minutes", type=float, default=0,
                        help="wall-clock budget; stops cleanly after the epoch that crosses it")
    parser.add_argument("--label-smoothing", type=float, default=0.05)
    parser.add_argument("--resume", action="store_true",
                        help="continue from models/<stem>.ckpt")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    if not os.path.isdir(args.data):
        raise SystemExit(
            f"No such dataset directory: {args.data}\n"
            "Build it first:  python tools/build_leaf_dataset.py"
        )

    torch.manual_seed(args.seed)
    random.seed(args.seed)
    torch.set_num_threads(max(1, (os.cpu_count() or 4)))

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}  threads: {torch.get_num_threads()}")

    train_transform, val_transform = build_transforms(args.img_size)
    base = datasets.ImageFolder(args.data)
    class_names = base.classes
    if len(class_names) < 2:
        raise SystemExit("Need at least two class directories to train a classifier.")

    train_indices, val_indices = stratified_split(base, args.val_split, args.seed)
    train_set = TransformedSubset(base, train_indices, train_transform)
    val_set = TransformedSubset(base, val_indices, val_transform)

    # Origins for the validation set, in loader order (shuffle=False below).
    val_origins = [origin_of(base.samples[i][0]) for i in val_indices]
    field_total = sum(1 for o in val_origins if o == "field")

    print(f"{len(base.samples)} images, {len(class_names)} classes")
    print(f"  train {len(train_set)}   val {len(val_set)}  (field images in val: {field_total})")

    loader_kwargs = {"num_workers": args.workers, "pin_memory": False}
    if args.workers > 0:
        loader_kwargs["persistent_workers"] = True
        loader_kwargs["prefetch_factor"] = 4
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True,
                              drop_last=True, **loader_kwargs)
    val_loader = DataLoader(val_set, batch_size=args.batch_size, shuffle=False,
                            **loader_kwargs)

    model = build_model(args.arch, len(class_names), args.freeze_until).to(device)
    trainable = [p for p in model.parameters() if p.requires_grad]
    frozen = sum(1 for p in model.parameters() if not p.requires_grad)
    print(f"  {arch_summary(model)}  trainable tensors: {len(trainable)}  frozen: {frozen}")

    train_targets = [base.samples[i][1] for i in train_indices]
    criterion = nn.CrossEntropyLoss(
        weight=class_weights(train_targets, len(class_names)).to(device),
        label_smoothing=args.label_smoothing,
    )
    optimiser = torch.optim.AdamW(trainable, lr=args.lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimiser, T_max=args.epochs)

    os.makedirs(args.out, exist_ok=True)
    model_path = os.path.join(args.out, f"{args.stem}.pt")
    labels_path = os.path.join(args.out, f"{args.stem}_labels.txt")
    report_path = os.path.join(args.out, f"{args.stem}_report.json")
    ckpt_path = os.path.join(args.out, f"{args.stem}.ckpt")

    start_epoch, best_accuracy = 1, 0.0
    if args.resume and os.path.isfile(ckpt_path):
        state = torch.load(ckpt_path, map_location=device, weights_only=False)
        model.load_state_dict(state["model"])
        optimiser.load_state_dict(state["optimiser"])
        scheduler.load_state_dict(state["scheduler"])
        start_epoch = state["epoch"] + 1
        best_accuracy = state.get("best_accuracy", 0.0)
        print(f"  resumed from epoch {state['epoch']} (best val {best_accuracy:.3f})")

    started = time.time()
    history = []

    budget_seconds = args.max_minutes * 60 if args.max_minutes else 0
    out_of_time = False

    for epoch in range(start_epoch, args.epochs + 1):
        model.train()
        running, seen = 0.0, 0
        epoch_started = time.time()

        for step, (images, labels) in enumerate(train_loader, 1):
            images, labels = images.to(device), labels.to(device)
            optimiser.zero_grad(set_to_none=True)
            loss = criterion(model(images), labels)
            loss.backward()
            optimiser.step()

            running += loss.detach().item() * images.size(0)
            seen += images.size(0)
            if step % 25 == 0:
                rate = seen / max(1e-6, time.time() - epoch_started)
                remaining = (len(train_set) - seen) / max(1e-6, rate)
                print(f"\r  epoch {epoch} step {step}/{len(train_loader)}  "
                      f"loss {running / max(1, seen):.4f}  "
                      f"{rate:.1f} img/s  ~{remaining / 60:.1f} min left",
                      end="", flush=True)

                # Enforce the budget *inside* the epoch, not just between
                # epochs. On an unfamiliar box one epoch can take longer than
                # the whole budget, and a between-epochs check would sail past
                # it by hours. Cutting the epoch short still leaves a trained,
                # validated, exported model — just fewer steps than planned.
                if budget_seconds and time.time() - started >= budget_seconds:
                    print(f"\n  budget reached mid-epoch at step {step}; "
                          f"finishing this epoch early")
                    out_of_time = True
                    break
        print()
        scheduler.step()

        accuracy, recalls, by_origin, worst = evaluate(
            model, val_loader, device, class_names, val_origins
        )
        elapsed = (time.time() - started) / 60.0
        field = by_origin.get("field", {}).get("accuracy")
        print(f"  epoch {epoch:2d}/{args.epochs}  loss {running / max(1, seen):.4f}  "
              f"val_acc {accuracy:.3f}  "
              f"lab {by_origin.get('lab', {}).get('accuracy')}  "
              f"field {field}  [{elapsed:.1f} min]")

        history.append({
            "epoch": epoch,
            "loss": round(running / max(1, seen), 4),
            "val_accuracy": round(accuracy, 4),
            "by_origin": by_origin,
        })

        torch.save({
            "model": model.state_dict(),
            "optimiser": optimiser.state_dict(),
            "scheduler": scheduler.state_dict(),
            "epoch": epoch,
            "best_accuracy": max(best_accuracy, accuracy),
            "classes": class_names,
            "args": vars(args),
        }, ckpt_path)

        if accuracy >= best_accuracy:
            best_accuracy = accuracy
            export(model, class_names, args.img_size, model_path, labels_path)
            with open(report_path, "w", encoding="utf-8") as handle:
                json.dump({
                    "task": "leaf-disease",
                    "arch": args.arch,
                    "img_size": args.img_size,
                    "classes": class_names,
                    "images": len(base.samples),
                    "val_accuracy": round(accuracy, 4),
                    "by_origin": by_origin,
                    "per_class_recall": recalls,
                    "worst_confusions": worst,
                    "epochs_run": epoch,
                    "history": history,
                    "sources": [
                        "PlantVillage (Mendeley doi:10.17632/tywbtsjrjv.1, CC0)",
                        "PlantDoc (github.com/pratikkayal/PlantDoc-Dataset, CC-BY-4.0)",
                    ],
                }, handle, indent=2)
            print(f"    exported (best so far) -> {model_path}")

        if out_of_time or (args.max_minutes and elapsed >= args.max_minutes):
            print(f"\nWall-clock budget of {args.max_minutes:.0f} min reached; stopping.")
            break

    minutes = (time.time() - started) / 60.0
    print(f"\nDone in {minutes:.1f} min. Best validation accuracy: {best_accuracy:.3f}")
    print(f"Model : {model_path}")
    print(f"Labels: {labels_path}")
    print(f"Report: {report_path}")
    print(
        "\nEnable it in backend/my_flask_app/.env and restart:\n"
        f"  AI_DISEASE_MODEL_PATH={os.path.abspath(model_path)}\n"
        f"  AI_DISEASE_LABELS_PATH={os.path.abspath(labels_path)}"
    )


def arch_summary(model) -> str:
    total = sum(p.numel() for p in model.parameters())
    return f"{total / 1e6:.1f}M params"


if __name__ == "__main__":
    main()
