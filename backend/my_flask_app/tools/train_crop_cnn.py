#!/usr/bin/env python
"""Fine-tune a pretrained CNN for MP crop disease or weed species.

Produces exactly the two files the backend loads at runtime — a TorchScript
module and a labels file — so training and serving cannot drift apart:

    python tools/train_crop_cnn.py --data datasets/crop_disease --task disease
    -> models/crop_disease.pt
       models/crop_disease_labels.txt

Point the backend at them and restart:

    AI_CROP_MODEL_PATH=/abs/path/models/crop_disease.pt
    AI_CROP_LABELS_PATH=/abs/path/models/crop_disease_labels.txt

Dataset layout is torchvision's ``ImageFolder`` — one directory per class:

    datasets/crop_disease/
        soybean_yellow_mosaic/   img001.jpg ...
        wheat_yellow_rust/       ...
        rice_blast/              ...
        healthy/                 ...

**Name the folders after the knowledge-base ids** in ``app/ai/crop_kb.py``
(``wheat_yellow_rust``, ``rice_brown_spot``, …). The label mapper in
``app/ai/crop_model.py`` will do its best with a public dataset's own names —
``Wheat___Yellow_Rust``, ``BrownSpot`` — but an exact id needs no guessing at
all, and a label it cannot map is reported to the operator as unmapped rather
than shown as a diagnosis.

Transfer learning is the right tool here: the public Indian-crop datasets run
to a few thousand images per class at best, which is nowhere near enough to
train a CNN from scratch, and a backbone pretrained on ImageNet already knows
edges, texture and leaf shape. See ``docs/CROP_CNN_TRAINING.md`` for the
dataset sources and the accuracy to expect.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from collections import Counter

try:
    import torch
    from torch import nn
    from torch.utils.data import DataLoader, random_split
    from torchvision import datasets, models, transforms
except ImportError:  # pragma: no cover - the tool is optional
    sys.exit(
        "This trainer needs PyTorch. Install it first:\n"
        "    pip install torch torchvision\n"
        "(The backend itself does not need torch — it falls back to the "
        "OpenCV heuristic when no model is configured.)"
    )


# Backbones worth using here, smallest first. MobileNet is the one to pick if
# the model will ever run on the drone's companion computer rather than a
# server; ResNet-18 is the safe default on a laptop.
ARCHITECTURES = {
    "mobilenet_v3_large": (models.mobilenet_v3_large, models.MobileNet_V3_Large_Weights.DEFAULT),
    "resnet18": (models.resnet18, models.ResNet18_Weights.DEFAULT),
    "resnet50": (models.resnet50, models.ResNet50_Weights.DEFAULT),
    "efficientnet_b0": (models.efficientnet_b0, models.EfficientNet_B0_Weights.DEFAULT),
}

IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]


def build_transforms(img_size: int):
    """Augmentation that matches how the frames are actually taken.

    Flips and rotations are free accuracy here: a drone frame has no canonical
    "up", so a model that has only seen upright leaves will do badly on half
    the pass. Colour jitter stands in for the difference between a 9 a.m. and
    a 2 p.m. flight.
    """
    train = transforms.Compose([
        transforms.RandomResizedCrop(img_size, scale=(0.6, 1.0)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomVerticalFlip(),
        transforms.RandomRotation(25),
        transforms.ColorJitter(brightness=0.25, contrast=0.25, saturation=0.2, hue=0.03),
        transforms.ToTensor(),
        transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
    ])
    validate = transforms.Compose([
        transforms.Resize(int(img_size * 1.15)),
        transforms.CenterCrop(img_size),
        transforms.ToTensor(),
        transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
    ])
    return train, validate


def build_model(arch: str, num_classes: int, freeze_backbone: bool):
    if arch not in ARCHITECTURES:
        raise SystemExit(
            f"Unknown --arch '{arch}'. Choose from: {', '.join(ARCHITECTURES)}"
        )
    factory, weights = ARCHITECTURES[arch]
    model = factory(weights=weights)

    if freeze_backbone:
        for parameter in model.parameters():
            parameter.requires_grad = False

    # Swap the ImageNet head for one with our class count. Every torchvision
    # family names it differently, hence the three branches.
    if hasattr(model, "fc"):                      # ResNet
        model.fc = nn.Linear(model.fc.in_features, num_classes)
    elif hasattr(model, "classifier"):
        classifier = model.classifier
        if isinstance(classifier, nn.Sequential):  # MobileNet / EfficientNet
            for index in range(len(classifier) - 1, -1, -1):
                if isinstance(classifier[index], nn.Linear):
                    classifier[index] = nn.Linear(classifier[index].in_features, num_classes)
                    break
        else:
            model.classifier = nn.Linear(classifier.in_features, num_classes)
    else:  # pragma: no cover - future torchvision layouts
        raise SystemExit(f"Don't know how to replace the head of {arch}.")

    return model


def class_weights(dataset, num_classes: int, indices) -> torch.Tensor:
    """Inverse-frequency weights so rare diseases are not simply ignored.

    Real field datasets are lopsided — 'healthy' outnumbers every disease
    several times over — and an unweighted loss happily reaches 80% accuracy
    by predicting 'healthy' for everything, which is worse than useless to a
    farmer looking for the 20%.
    """
    counts = Counter(dataset.targets[i] for i in indices)
    total = sum(counts.values())
    weights = [
        total / (num_classes * counts.get(index, 1)) for index in range(num_classes)
    ]
    return torch.tensor(weights, dtype=torch.float32)


def evaluate(model, loader, device, class_names):
    model.eval()
    correct = total = 0
    per_class = {name: [0, 0] for name in class_names}  # [correct, seen]

    with torch.no_grad():
        for images, labels in loader:
            images, labels = images.to(device), labels.to(device)
            predictions = model(images).argmax(dim=1)
            correct += int((predictions == labels).sum())
            total += labels.size(0)
            for label, prediction in zip(labels.tolist(), predictions.tolist()):
                name = class_names[label]
                per_class[name][1] += 1
                if label == prediction:
                    per_class[name][0] += 1

    accuracy = correct / total if total else 0.0
    recalls = {
        name: round(hit / seen, 3) if seen else None
        for name, (hit, seen) in per_class.items()
    }
    return accuracy, recalls


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", required=True, help="ImageFolder root (one directory per class)")
    parser.add_argument("--task", choices=("disease", "weed"), default="disease")
    parser.add_argument("--out", default="models", help="where to write the model + labels")
    parser.add_argument("--arch", default="resnet18", choices=sorted(ARCHITECTURES))
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--img-size", type=int, default=224)
    parser.add_argument("--val-split", type=float, default=0.2)
    parser.add_argument("--freeze-backbone", action="store_true",
                        help="train the head only — much faster, use on small datasets")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    if not os.path.isdir(args.data):
        raise SystemExit(f"No such dataset directory: {args.data}")

    torch.manual_seed(args.seed)
    random.seed(args.seed)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    train_transform, val_transform = build_transforms(args.img_size)
    full = datasets.ImageFolder(args.data, transform=train_transform)
    class_names = full.classes
    if len(class_names) < 2:
        raise SystemExit("Need at least two class directories to train a classifier.")
    print(f"{len(full)} images across {len(class_names)} classes: {', '.join(class_names)}")

    val_size = max(1, int(len(full) * args.val_split))
    train_size = len(full) - val_size
    generator = torch.Generator().manual_seed(args.seed)
    train_set, val_set = random_split(full, [train_size, val_size], generator=generator)

    # The validation split must not see the training augmentation, or the
    # accuracy it reports is measuring a harder problem than the real one.
    val_base = datasets.ImageFolder(args.data, transform=val_transform)
    val_set.dataset = val_base

    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True, num_workers=0)
    val_loader = DataLoader(val_set, batch_size=args.batch_size, shuffle=False, num_workers=0)

    model = build_model(args.arch, len(class_names), args.freeze_backbone).to(device)
    weights = class_weights(full, len(class_names), train_set.indices).to(device)
    criterion = nn.CrossEntropyLoss(weight=weights)
    trainable = [p for p in model.parameters() if p.requires_grad]
    optimiser = torch.optim.AdamW(trainable, lr=args.lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimiser, T_max=args.epochs)

    os.makedirs(args.out, exist_ok=True)
    stem = "crop_disease" if args.task == "disease" else "weed_species"
    model_path = os.path.join(args.out, f"{stem}.pt")
    labels_path = os.path.join(args.out, f"{stem}_labels.txt")

    best_accuracy = 0.0
    started = time.time()

    for epoch in range(1, args.epochs + 1):
        model.train()
        running = 0.0
        for images, labels in train_loader:
            images, labels = images.to(device), labels.to(device)
            optimiser.zero_grad()
            loss = criterion(model(images), labels)
            loss.backward()
            optimiser.step()
            running += float(loss) * images.size(0)
        scheduler.step()

        accuracy, recalls = evaluate(model, val_loader, device, class_names)
        print(
            f"epoch {epoch:2d}/{args.epochs}  "
            f"loss {running / max(1, train_size):.4f}  val_acc {accuracy:.3f}"
        )

        if accuracy >= best_accuracy:
            best_accuracy = accuracy
            # Export on improvement, so an interrupted run still leaves the
            # best model on disk rather than nothing.
            model.eval()
            example = torch.randn(1, 3, args.img_size, args.img_size, device=device)
            scripted = torch.jit.trace(model, example)
            scripted.save(model_path)
            with open(labels_path, "w", encoding="utf-8") as handle:
                handle.write("\n".join(class_names) + "\n")
            with open(os.path.join(args.out, f"{stem}_report.json"), "w", encoding="utf-8") as handle:
                json.dump(
                    {
                        "task": args.task,
                        "arch": args.arch,
                        "classes": class_names,
                        "val_accuracy": round(accuracy, 4),
                        "per_class_recall": recalls,
                        "epochs_run": epoch,
                        "images": len(full),
                        "img_size": args.img_size,
                    },
                    handle,
                    indent=2,
                )

    minutes = (time.time() - started) / 60.0
    print(f"\nDone in {minutes:.1f} min. Best validation accuracy: {best_accuracy:.3f}")
    print(f"Model : {model_path}")
    print(f"Labels: {labels_path}")
    env = "AI_CROP" if args.task == "disease" else "AI_WEED"
    print(
        "\nEnable it in the backend's .env:\n"
        f"  {env}_MODEL_PATH={os.path.abspath(model_path)}\n"
        f"  {env}_LABELS_PATH={os.path.abspath(labels_path)}"
    )


if __name__ == "__main__":
    main()
