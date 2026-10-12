import Testing
@testable import DevDock

@Suite struct ShellAliasesTests {
    let home = "/Users/me"

    @Test func readsClaudeConfigDirAliases() {
        let rc = """
        alias claude-work='CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude'
        alias claude-side="CLAUDE_CONFIG_DIR=~/.claude-side claude --verbose"
          alias cw=CLAUDE_CONFIG_DIR=${HOME}/.claude-x claude
        """
        #expect(ShellAliases.parse(rc, home: home) == [
            "/Users/me/.claude-work": "claude-work",
            "/Users/me/.claude-side": "claude-side",
            "/Users/me/.claude-x": "cw",
        ])
    }

    @Test func ignoresOtherCommandsAndComments() {
        let rc = """
        alias code-work='CLAUDE_CONFIG_DIR="$HOME/.claude-work" code --new-window'
        # alias old='CLAUDE_CONFIG_DIR="$HOME/.claude-old" claude'
        export CLAUDE_CONFIG_DIR="$HOME/.claude-work"
        """
        #expect(ShellAliases.parse(rc, home: home).isEmpty)
    }
}
