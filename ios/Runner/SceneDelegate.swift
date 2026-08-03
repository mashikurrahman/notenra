import Flutter
import UIKit

/// iOS has no direct equivalent of Android's FLAG_SECURE, so we approximate the
/// PHI-protection behaviour by covering the UI with a blurred overlay whenever
/// the app leaves the foreground. This keeps patient data out of the app
/// switcher snapshot and screen recordings of the multitasking view.
class SceneDelegate: FlutterSceneDelegate {

  private var privacyOverlay: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    showPrivacyOverlay(in: scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    hidePrivacyOverlay()
  }

  private func showPrivacyOverlay(in scene: UIScene) {
    guard privacyOverlay == nil,
          let windowScene = scene as? UIWindowScene,
          let window = windowScene.windows.first else { return }

    let blur = UIBlurEffect(style: .systemMaterial)
    let overlay = UIVisualEffectView(effect: blur)
    overlay.frame = window.bounds
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(overlay)
    privacyOverlay = overlay
  }

  private func hidePrivacyOverlay() {
    privacyOverlay?.removeFromSuperview()
    privacyOverlay = nil
  }
}
