# TestFlight metadata — English (U.S.)

## Beta description

Test Tessalytics, a privacy-focused native companion for self-hosted TeslaMate
data on iPhone, iPad, and Mac. Connect your own Tessalytics Backend — the
read-only API service you deploy beside TeslaMate — to review vehicle status,
offline drive and charging history, native analytics, battery-health estimates,
forecasts, and local alerts. Server settings and credentials follow your Apple
Account through iCloud. Optional Owner API connectivity adds confirmed,
device-authenticated controls. Please report your Tessalytics Backend version,
your device, and the affected screen when sending feedback, but never include
tokens, VINs, routes, addresses, or precise locations.

## What to Test — 1.1.0 (5)

Build 5 adds explicit units throughout status, drive, charging, analytics,
battery, and forecast screens; improves compatibility with protected
TeslaMateApi deployments; refines the compact vehicle dashboard; and includes
the latest native charts, forecasts, local alerts, and optional confirmed Owner
API controls. Please focus testing on server onboarding, freshness labels,
metric units, offline history, and navigation.

The private TestFlight feedback email is configured directly in App Store
Connect and is intentionally excluded from this public metadata file.

## What to Test — 1.0.3 (202608191804)

This build adds **Explore Demo** for people without a Tesla or TeslaMate server.
The app generates about two months of private, on-device sample drives, routes,
charging sessions, software updates, battery trends, analytics, and forecasts.
Please test entering Demo Mode from first-launch onboarding, relaunch persistence,
charts and history details, leaving Demo Mode, and connecting a real server.
Direct vehicle controls must remain hidden while using generated demo data.
