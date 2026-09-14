# Project principles

SwiftNote is a quick native macOS memo app. Keep the default surface quiet, restore directly into the editor, and avoid network dependencies or workspace navigation.

For UI changes, an independent reviewer must inspect real screenshots and the affected interactions before delivery. Cover alignment, typography, spacing, contrast, narrow windows, and light/dark appearances. Do not treat a screenshot as proof of interaction behavior.

Use isolated data with LOCALNOTES_DATA_DIR for tests. Never use a real memo store in fixtures or screenshots. Run ./test.sh for editing or persistence changes; build with ./build.sh. Keep macOS 14 deployment compatibility. Generated apps and release archives are excluded from source control.
