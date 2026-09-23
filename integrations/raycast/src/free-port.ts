import { Clipboard, Toast, showHUD, showToast } from "@raycast/api";
import { portly } from "./portly";

export default async function Command() {
  try {
    const port = (await portly(["free"])).trim();
    await Clipboard.copy(port);
    await showHUD(`Copied free port ${port}`);
  } catch (e) {
    await showToast({ style: Toast.Style.Failure, title: "No free port", message: e instanceof Error ? e.message : String(e) });
  }
}
