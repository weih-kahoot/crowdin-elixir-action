defmodule Mix.Tasks.Crowdin do
  use Mix.Task
  alias CrowdinElixirAction.Crowdin

  def run(workspace) do
    token = System.get_env("INPUT_TOKEN")
    project_id = System.get_env("INPUT_PROJECT_ID")
    source_file = System.get_env("INPUT_SOURCE_FILE")

    sync(workspace, token, project_id, source_file)
    |> IO.inspect
  end

  def upload_source(workspace, client, project_id, source_file) do
    path = Path.join(workspace, source_file)
    source_name = Path.basename(source_file)
    with {:ok, res} <- Crowdin.add_storage(client, path),
         201 <- res.status,
         %{"data" => %{"id" => storage_id}} <- res.body,
         {:ok, res} <- Crowdin.list_files(client, project_id),
         200 <- res.status do
      case Enum.find(res.body["data"], fn file -> file["data"]["name"] == source_name end) do
        nil -> Crowdin.add_file(client, project_id, storage_id, source_name)
        file -> Crowdin.update_file(client, project_id, file["data"]["id"], storage_id)
      end
    end
  end

  defp sync(workspace, token, project_id, source_file) do
    client = Crowdin.client(token)
    upload_source(workspace, client, project_id, source_file)
#    with {:ok, res} <- Crowdin.
  end
end