import Defaults

/// Top-level modules of the panel. Add a case here to register a new module.
nonisolated enum AppModule: String, CaseIterable, Identifiable, Defaults.Serializable {
    case ports
    case aiUsage
    case claudeMem
    case projects
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .ports: "Ports"
        case .aiUsage: "AI"
        case .claudeMem: "Memory"
        case .projects: "Projects"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .ports: "network"
        case .aiUsage: "sparkles"
        case .claudeMem: "brain"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }

    /// Modules shown as tabs in the header. Settings is reached from the footer.
    static let headerModules: [AppModule] = [.ports, .aiUsage, .claudeMem, .projects]
}
