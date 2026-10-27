import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { PlaylistPage } from './PlaylistPage';
import { SearchPage } from './SearchPage';
import { PlayerPage } from './PlayerPage';

@Entry
@Component
struct Index {
  @Provide('nav') pathStack: NavPathStack = new NavPathStack();

  @Builder
  pageMap(name: string) {
    if (name === 'login') {
      LoginPage()
    } else if (name === 'playlist') {
      PlaylistPage()
    } else if (name === 'search') {
      SearchPage()
    } else if (name === 'player') {
      PlayerPage()
    }
  }

  build() {
    Navigation(this.pathStack) {
      HomePage()
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .focusable(true)
    .navDestination(this.pageMap)
    .backgroundColor($r('app.color.nm_bg'))
  }
}
