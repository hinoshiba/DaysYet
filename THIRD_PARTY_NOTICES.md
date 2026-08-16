# Third-party notices

The iOS application and Widget extension currently ship with **no third-party runtime code, fonts, images, analytics SDKs, or advertising SDKs**.

The following development tool is not bundled in the distributed application:

| Tool | Version | License | Purpose |
|---|---:|---|---|
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 2.45.4 | MIT | Generates the Xcode project from `project.yml` |
| [ImageMagick](https://imagemagick.org/) | 7.1.2-27 | ImageMagick License | Removes the alpha channel from optional Simulator screenshot captures; not used by the app build |

Apple frameworks, system fonts, and SF Symbols are provided by the operating system and are used only in Apple-platform application UI under the applicable Apple developer agreements. They are not redistributed as standalone assets.

This inventory must be reviewed whenever a dependency, font, image, sound, dataset, or SDK is added.
