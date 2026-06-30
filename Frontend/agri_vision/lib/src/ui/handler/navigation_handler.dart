import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';

enum Menu { home, settings, maps, alerts, reports }

class SidebarState {
  const SidebarState({this.selectedMenu = Menu.home});

  final Menu selectedMenu;
}

class SidebarCubit extends Cubit<SidebarState> {
  SidebarCubit() : super(const SidebarState());

  void selectMenu(Menu menu) => emit(SidebarState(selectedMenu: menu));
}

class NavigationHandler extends StatelessWidget {
  const NavigationHandler({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<SidebarCubit, SidebarState>(
      listenWhen: (prev, curr) => prev.selectedMenu != curr.selectedMenu,
      listener: (_, state) {
        final navigator = AppRouter.navigationKey.currentState;
        if (navigator == null) return;

        switch (state.selectedMenu) {
          case Menu.home:
            navigator.pushReplacementNamed(AppRouterNames.home);
            break;
          case Menu.settings:
            navigator.pushReplacementNamed(AppRouterNames.settings);
            break;
          case Menu.maps:
            navigator.pushReplacementNamed(AppRouterNames.maps);
            break;
          case Menu.alerts:
            navigator.pushReplacementNamed(AppRouterNames.alerts);
            break;
          case Menu.reports:
            navigator.pushReplacementNamed(AppRouterNames.reports);
            break;
        }
      },
      child: child,
    );
  }
}
