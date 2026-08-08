import PostcatExampleCore
import TermLoom

let renderingMode: PostcatRenderingMode =
  CommandLine.arguments.contains("--observable") ? .observation : .explicit
let application = PostcatApplication(renderingMode: renderingMode)
try await application.run(viewport: .fullscreen)
