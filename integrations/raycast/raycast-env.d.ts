/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `ports` command */
  export type Ports = ExtensionPreferences & {}
  /** Preferences accessible in the `free-port` command */
  export type FreePort = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `ports` command */
  export type Ports = {}
  /** Arguments passed to the `free-port` command */
  export type FreePort = {}
}

