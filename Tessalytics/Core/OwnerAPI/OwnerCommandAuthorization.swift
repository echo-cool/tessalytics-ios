import LocalAuthentication

enum OwnerCommandAuthorization {
    @MainActor
    static func request(for command: OwnerVehicleCommand) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Confirm \(command.title.lowercased()) for your Tesla."
            )
        } catch {
            return false
        }
    }
}
