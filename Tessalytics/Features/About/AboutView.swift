import SwiftUI

struct AboutView: View {
    var body: some View {
        TessalyticsScreen {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 50))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(TessalyticsTheme.accent)
                            .frame(width: 84, height: 84)
                            .background(TessalyticsTheme.accent.opacity(0.10), in: .circle)
                            .accessibilityHidden(true)
                        Text("Tessalytics").font(.title.bold())
                        Text("Live Vehicle Data").foregroundStyle(.secondary)
                        Text("A Open Source TeslaMate Client").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                Section {
                    Link(destination: URL(string: "https://github.com/echo-cool/tessalytics-ios")!) {
                        Label("iPhone app", systemImage: "iphone")
                    }
                    Link(destination: URL(string: "https://github.com/echo-cool/tessalytics-backend")!) {
                        Label("Backend", systemImage: "server.rack")
                    }
                    Link(destination: URL(string: "https://github.com/echo-cool/tessalytics-web")!) {
                        Label("Web dashboard", systemImage: "macbook.and.iphone")
                    }
                } header: {
                    Label("Open source", systemImage: "chevron.left.forwardslash.chevron.right")
                } footer: {
                    Text("All three are open source. Issues and pull requests are welcome.")
                }

                // The licence, in the app rather than only in the repository.
                // Distributing a copy of AGPL software means telling the person
                // holding it what its terms are and where the source is — and on
                // the App Store this screen is the only place that can happen.
                Section {
                    Text("Tessalytics is free software under the GNU Affero General Public License, version 3 or later. You may use, study, modify and share it; a modified version offered to others over a network must offer them its source.")
                    Link("Licence (AGPL-3.0-or-later)", destination: URL(string: "https://github.com/echo-cool/tessalytics-ios/blob/main/LICENSE")!)
                    Link("Source code", destination: URL(string: "https://github.com/echo-cool/tessalytics-ios")!)
                    Link("Trademark policy", destination: URL(string: "https://github.com/echo-cool/tessalytics-ios/blob/main/TRADEMARK.md")!)
                } header: {
                    Label("Licence", systemImage: "doc.text")
                } footer: {
                    Text("The licence covers the code. The Tessalytics name and icon are covered by the trademark policy.")
                }

                Section {
                    Text("This project is an unofficial community tool and is not affiliated with, endorsed by, or supported by the official TeslaMate project or Tesla, Inc. \"TeslaMate\" and \"Tesla\" are the trademarks of their respective owners and are used here only to say what this app connects to.")
                    Link("TeslaMate", destination: URL(string: "https://github.com/teslamate-org/teslamate")!)
                    Link("TeslaMate trademark policy", destination: URL(string: "https://github.com/teslamate-org/teslamate/blob/main/TRADEMARK.md")!)
                } header: {
                    Label("Community project", systemImage: "person.2.fill")
                }
                Section("Safety") {
                    Label("Owner API commands are optional and require confirmation plus Face ID or the device passcode. Tessalytics never wakes a sleeping vehicle automatically.", systemImage: "hand.raised.fill")
                        .foregroundStyle(TessalyticsTheme.warning)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("About")
    }
}

struct PrivacyView: View {
    var body: some View {
        TessalyticsScreen {
            List {
                Section { Text("Tessalytics connects directly from this device to each TeslaMate server and, when enabled, Tesla's Owner API. No Tessalytics-operated service receives your vehicle data.") } header: { Label("Direct connection", systemImage: "network") }
                Section { Text("Server credentials are stored in iOS Keychain. Owner API tokens use When Unlocked, This Device Only protection and are never stored in app preferences or the offline database.") } header: { Label("Credentials", systemImage: "key.fill") }
                Section { Text("Historical drives, routes, charging sessions, battery estimates, and updates may be stored on this device for offline use and are partitioned by server and vehicle.") } header: { Label("Local data", systemImage: "internaldrive.fill") }
                Section { Text("Tessalytics contains no advertising, analytics SDK, or third-party tracking.") } header: { Label("No tracking", systemImage: "hand.raised.fill") }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Privacy")
    }
}
