import DiffScopeExampleCore
import Foundation
import TermLoom

let arguments = Array(CommandLine.arguments.dropFirst())
let configuration = try await DiffScopeConfiguration.resolve(arguments: arguments)
let application = DiffScopeApplication(
  repository: configuration.repository,
  diffLoader: configuration.diffLoader
)
await application.prepare()
try await application.run(viewport: .fullscreen, capturesMouse: true)
