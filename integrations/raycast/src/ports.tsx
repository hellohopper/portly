import {
  Action,
  ActionPanel,
  Alert,
  Color,
  Icon,
  List,
  Toast,
  confirmAlert,
  open,
  showToast,
} from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import { PortRow, describe, listPorts, portly } from "./portly";

export default function Command() {
  const [rows, setRows] = useState<PortRow[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string>();

  const refresh = useCallback(async () => {
    setIsLoading(true);
    try {
      setRows(await listPorts());
      setError(undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  if (error) {
    return (
      <List>
        <List.EmptyView icon={Icon.ExclamationMark} title="Couldn't read ports" description={error} />
      </List>
    );
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter by port, process, framework or project">
      {rows.map((row) => (
        <PortItem key={`${row.pid}-${row.port}-${row.proto}`} row={row} onChange={refresh} />
      ))}
    </List>
  );
}

function PortItem({ row, onChange }: { row: PortRow; onChange: () => Promise<void> }) {
  const url = `http://localhost:${row.port}`;
  const isTCP = row.proto.includes("TCP");
  const project = row.projectName ? (row.gitBranch ? `${row.projectName} · ${row.gitBranch}` : row.projectName) : undefined;

  const accessories: List.Item.Accessory[] = [];
  if (row.exposedToNetwork === "true") {
    accessories.push({ tag: { value: "LAN", color: Color.Orange }, tooltip: "Reachable from your network" });
  }
  if (project) accessories.push({ text: project, icon: Icon.Folder });
  accessories.push({ text: `pid ${row.pid}` });

  async function kill(force: boolean) {
    const confirmed = await confirmAlert({
      title: `${force ? "Force kill" : "Kill"} ${describe(row)} on port ${row.port}?`,
      primaryAction: { title: force ? "Force Kill" : "Kill", style: Alert.ActionStyle.Destructive },
    });
    if (!confirmed) return;
    const toast = await showToast({ style: Toast.Style.Animated, title: `Stopping port ${row.port}…` });
    try {
      await portly(["kill", row.port, ...(force ? ["--force"] : [])]);
      toast.style = Toast.Style.Success;
      toast.title = `Stopped port ${row.port}`;
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = `Port ${row.port} is still running`;
      toast.message = force ? String(e) : "Try Force Kill";
    }
    await onChange();
  }

  async function restart() {
    const toast = await showToast({ style: Toast.Style.Animated, title: `Restarting port ${row.port}…` });
    try {
      await portly(["restart", row.port]);
      toast.style = Toast.Style.Success;
      toast.title = `Restarted ${describe(row)}`;
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = "Restart failed";
      toast.message = String(e);
    }
    await onChange();
  }

  return (
    <List.Item
      title={row.port}
      subtitle={describe(row)}
      icon={{ source: Icon.CircleFilled, tintColor: Color.Green }}
      keywords={[row.processName, row.frameworkLabel, row.projectName, row.gitBranch, row.proto].filter(Boolean)}
      accessories={accessories}
      actions={
        <ActionPanel>
          {isTCP && <Action.OpenInBrowser url={url} />}
          {isTCP && <Action.CopyToClipboard title="Copy URL" content={url} />}
          <Action title="Restart" icon={Icon.ArrowClockwise} shortcut={{ modifiers: ["cmd"], key: "r" }} onAction={restart} />
          <Action
            title="Kill"
            icon={Icon.XMarkCircle}
            style={Action.Style.Destructive}
            shortcut={{ modifiers: ["ctrl"], key: "x" }}
            onAction={() => kill(false)}
          />
          <Action
            title="Force Kill (SIGKILL)"
            icon={Icon.XMarkCircleFilled}
            style={Action.Style.Destructive}
            shortcut={{ modifiers: ["ctrl", "shift"], key: "x" }}
            onAction={() => kill(true)}
          />
          <Action title="Pin in Portly" icon={Icon.Pin} onAction={() => open(`portly://pin/${row.port}`)} />
          <Action title="Show in Portly" icon={Icon.AppWindow} onAction={() => open(`portly://show?search=${row.port}`)} />
          <Action.CopyToClipboard title="Copy PID" content={row.pid} />
          <Action title="Refresh" icon={Icon.RotateClockwise} shortcut={{ modifiers: ["cmd", "shift"], key: "r" }} onAction={onChange} />
        </ActionPanel>
      }
    />
  );
}
