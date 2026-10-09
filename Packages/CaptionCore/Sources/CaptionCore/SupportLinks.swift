import Foundation

/// The public privacy policy and support pages, published from the repo's site/ folder by .github/workflows/pages.yml.
/// The App Review Guidelines (5.1.1(i)) want the privacy policy reachable inside the app, not only on the store page.
public enum SupportLinks {
    /// One base for both pages: moving to a custom domain (#46) changes only this line.
    public static let base = URL(string: "https://g-eskayo.github.io/clarity-captions/")!

    public static let privacyPolicy = base.appendingPathComponent("privacy.html")
    public static let support = base.appendingPathComponent("support.html")
}
