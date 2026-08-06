#if os(macOS)
import AppKit
import Foundation

extension KeyboardShortcuts {
	/**
	A currently enabled, user-configurable system keyboard shortcut.
	*/
	public struct SystemShortcutConflict: Hashable, Sendable {
		/**
		The keyboard shortcut assigned by macOS.
		*/
		public let shortcut: Shortcut

		/**
		The symbolic hotkey identifier used by macOS.
		*/
		public let identifier: Int

		/**
		The action name shown in System Settings, when it can be determined.
		*/
		public let actionName: String?
	}
}

enum SystemShortcutProvider {
	private static let preferencesApplicationID = "com.apple.symbolichotkeys" as CFString
	private static let preferencesKey = "AppleSymbolicHotKeys" as CFString
	private static let keyboardSettingsResourcesURL = URL(
		fileURLWithPath: "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex/Contents/Resources",
		isDirectory: true
	)
	private static let shortcutIdentifierKeys = [
		"sybmolichotkey",
		"slow_sybmolichotkey",
		"prefs_sybmolichotkey"
	]
	private static let actionNames = loadActionNames()

	static var conflicts: [KeyboardShortcuts.SystemShortcutConflict] {
		_ = CFPreferencesAppSynchronize(preferencesApplicationID)

		guard let preferences = CFPreferencesCopyAppValue(preferencesKey, preferencesApplicationID) as? [String: Any] else {
			return []
		}

		return conflicts(from: preferences, actionNames: actionNames)
	}

	static func conflicts(
		from preferences: [String: Any],
		actionNames: [Int: String]
	) -> [KeyboardShortcuts.SystemShortcutConflict] {
		preferences.compactMap { identifierString, value in
			guard
				let identifier = Int(identifierString),
				let entry = value as? [String: Any],
				(entry["enabled"] as? Bool) == true,
				let shortcutValue = entry["value"] as? [String: Any],
				let parameters = shortcutValue["parameters"] as? [Any],
				parameters.count >= 3,
				let keyCode = (parameters[1] as? NSNumber)?.intValue,
				keyCode != Int(UInt16.max),
				let cocoaModifiers = (parameters[2] as? NSNumber)?.uintValue
			else {
				return nil
			}

			let shortcut = KeyboardShortcuts.Shortcut(
				carbonKeyCode: keyCode,
				carbonModifiers: NSEvent.ModifierFlags(rawValue: cocoaModifiers).carbon
			)

			return KeyboardShortcuts.SystemShortcutConflict(
				shortcut: shortcut,
				identifier: identifier,
				actionName: actionNames[identifier]
			)
		}
	}

	private static func loadActionNames() -> [Int: String] {
		let localizedNames = loadLocalizedNames()
		let definitionURLs = [
			keyboardSettingsResourcesURL.appendingPathComponent("en.lproj/DefaultShortcutsTable.xml"),
			keyboardSettingsResourcesURL.appendingPathComponent("DefaultSpacesShortcuts.xml")
		]
		var result = [Int: String]()

		for url in definitionURLs {
			guard
				let data = try? Data(contentsOf: url),
				let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil)
			else {
				continue
			}

			collectActionNames(from: propertyList, localizedNames: localizedNames, into: &result)
		}

		return result
	}

	private static func loadLocalizedNames() -> [String: String] {
		let url = keyboardSettingsResourcesURL.appendingPathComponent("DefaultShortcutsTable.loctable")

		guard
			let data = try? Data(contentsOf: url),
			let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
			let propertyListDictionary = propertyList as? [String: Any]
		else {
			return [:]
		}

		let localizations = propertyListDictionary.compactMapValues { $0 as? [String: String] }
		let availableLocalizations = Array(localizations.keys)
		let preferredLocalization = Bundle.preferredLocalizations(from: availableLocalizations).first

		return preferredLocalization.flatMap { localizations[$0] }
			?? localizations["en"]
			?? [:]
	}

	private static func collectActionNames(
		from value: Any,
		localizedNames: [String: String],
		into result: inout [Int: String]
	) {
		if let values = value as? [Any] {
			for value in values {
				collectActionNames(from: value, localizedNames: localizedNames, into: &result)
			}

			return
		}

		guard let dictionary = value as? [String: Any] else {
			return
		}

		if let rawName = dictionary["name"] as? String {
			let name = rawName.replacingOccurrences(of: "DO_NOT_LOCALIZE: ", with: "")
			let localizedName = localizedNames[name] ?? name

			for key in shortcutIdentifierKeys {
				if let identifier = (dictionary[key] as? NSNumber)?.intValue {
					result[identifier] = localizedName
				}
			}
		}

		if let elements = dictionary["elements"] {
			collectActionNames(from: elements, localizedNames: localizedNames, into: &result)
		}
	}
}
#endif
