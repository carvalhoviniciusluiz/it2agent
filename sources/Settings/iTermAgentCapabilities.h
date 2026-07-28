//
//  iTermAgentCapabilities.h
//  iTerm2 (it2agent fork)
//
//  Bridges the AI Settings pane to the it2agent feature-flag CLI
//  (it2agent/flags/it2agent-flag). The TOML at
//  ~/.config/it2agent/config.toml is the single source of truth; this class
//  never parses or writes it directly — every read and write is delegated to
//  it2agent-flag. All flags default OFF; if the CLI cannot be located, reads
//  return OFF and writes are no-ops so the UI fails safe.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermAgentCapabilities : NSObject

// Ordered list of capability identifiers (no prefix), mirroring KNOWN_FLAGS in
// it2agent-flag / it2agent_flag.py.
@property (class, nonatomic, readonly) NSArray<NSString *> *capabilityIdentifiers;

// The synthetic preference key for a capability, e.g. "agent.messaging".
+ (NSString *)preferenceKeyForCapability:(NSString *)capability;

// All synthetic preference keys, for registering placeholder defaults.
@property (class, nonatomic, readonly) NSArray<NSString *> *allPreferenceKeys;

// Human-readable label for a capability, e.g. "Worktree Isolation".
+ (NSString *)displayNameForCapability:(NSString *)capability;

// One-line, user-facing description of what a capability does, e.g.
// "Gives each agent its own git worktree and a dedicated port." Mirrors the
// KNOWN_FLAGS descriptions in it2agent-flag / it2agent_flag.py; shown next to
// each checkbox in the AI Agents settings pane.
+ (NSString *)descriptionForCapability:(NSString *)capability;

// YES if it2agent-flag was located and is runnable. When NO, the checkboxes
// should be disabled and all reads report OFF.
@property (class, nonatomic, readonly) BOOL available;

// Current on/off state of a capability, read (via a cached `list`) from the CLI.
+ (BOOL)isEnabledForCapability:(NSString *)capability;

// Toggle a capability by shelling out to `it2agent-flag enable|disable`.
+ (void)setEnabled:(BOOL)enabled forCapability:(NSString *)capability;

// Drops the cached `list` snapshot so the next read re-queries the CLI. Call
// when the pane appears so external TOML edits (feature flags) are reflected.
+ (void)invalidateCache;

#pragma mark - Team Bridge (project-scoped Claude Code hook)

// The Team Bridge capability is special: instead of flipping the global
// config.toml flag, it installs/removes a Claude Code hook in the ACTIVE
// project's gitignored .claude/settings.local.json (via it2agent-team-hook
// --scope project). These helpers shell out with `directory` as the working
// directory so the CLI resolves that project's git root.

// Resolve the team-bridge target for `directory` (a session's working
// directory). Returns YES if `directory` is inside a git repo (the checkbox can
// act); then *resolvedPath (optional) receives the settings.local.json path and
// *installed (optional) whether our hook is already present there. Returns NO if
// it2agent-team-hook is unavailable or `directory` is not in a git repo, in
// which case the checkbox should be disabled.
+ (BOOL)teamBridgeStatusForDirectory:(NSString *)directory
                        resolvedPath:(NSString * _Nullable * _Nullable)resolvedPath
                           installed:(nullable BOOL *)installed;

// Best-effort project-scoped install (installed=YES) or uninstall (NO) of the
// team-bridge hook for `directory`. Never throws; failures are logged.
+ (void)setTeamBridgeInstalled:(BOOL)installed forDirectory:(NSString *)directory;

#pragma mark - Autobrief discovery hook (user scope)

// The autobrief SessionStart discovery hook, installed at USER scope
// (~/.claude/settings.json via it2agent-autobrief-hook) so a fresh Claude Code
// session in any project, worktree, or machine self-discovers the it2agent
// agentic layer. The native Claude Code integration installs and self-heals it
// alongside cc-status.

// YES if it2agent-autobrief-hook is resolvable (so the app can act on the hook).
// When NO, the hook is not natively installable and its absence must not be
// treated as a broken integration.
+ (BOOL)autobriefDiscoveryHookAvailable;

// YES if our autobrief hook is present in ~/.claude/settings.json. NO when it is
// absent or the tool is unavailable.
+ (BOOL)autobriefDiscoveryHookInstalledUserScope;

// Best-effort user-scoped install (installed=YES) or uninstall (NO) of the
// autobrief discovery hook. Never throws; failures are logged.
+ (void)setAutobriefDiscoveryHookInstalledUserScope:(BOOL)installed;

@end

NS_ASSUME_NONNULL_END
