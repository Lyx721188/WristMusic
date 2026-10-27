import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NmStore } from '../common/NmStore';
import { NmPlayer } from '../common/NmPlayer';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private storeReady: Promise<void> = Promise.resolve();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      hilog.error(DOMAIN, 'NCMWatch', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    NmPlayer.init(this.context);
    this.storeReady = NmStore.init(this.context).catch((err: Object) => {
      hilog.error(DOMAIN, 'NCMWatch', 'store init failed: %{public}s', JSON.stringify(err));
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'NCMWatch', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Build the first page only after preferences have populated login and quality.
    this.storeReady.then(() => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'NCMWatch', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, 'NCMWatch', 'Succeeded in loading the content.');
      });
    });
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
