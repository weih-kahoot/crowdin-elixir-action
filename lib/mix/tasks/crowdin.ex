defmodule Mix.Tasks.Crowdin do
  use Mix.Task
  alias CrowdinElixirAction.Crowdin

  def run([workspace]) do
    IO.puts "Mix crowdin task #{inspect workspace}"

    token = System.get_env("INPUT_TOKEN")
    project_id = System.get_env("INPUT_PROJECT_ID")
    source_file = System.get_env("INPUT_SOURCE_FILE")

    sync(workspace, token, project_id, source_file) |> IO.inspect(label: :result)
  end

  def find_matching_remote_file(client, project_id, source_name) do
    with {:ok, res} <- Crowdin.list_files(client, project_id),
      200 <- res.status do
      Enum.find(res.body["data"], fn file -> file["data"]["name"] == source_name end)
    end
  end

  def upload_source(workspace, client, project_id, source_file) do
    IO.puts "Upload source"
    path = Path.join(workspace, source_file)
    source_name = Path.basename(source_file)
    with {:ok, res} <- Crowdin.add_storage(client, path),
         201 <- res.status,
         %{"data" => %{"id" => storage_id}} <- res.body do
      case find_matching_remote_file(client, project_id, source_name) do
        nil -> Crowdin.add_file(client, project_id, storage_id, source_name)
        file -> Crowdin.update_file(client, project_id, file["data"]["id"], storage_id)
      end
    end
  end

  def download_translation(workspace, client, project_id, file) do
    IO.puts "Download translation"
    with {:ok, res} <- Crowdin.get_project(client, project_id),
         200 <- res.status,
         %{"data" => %{"targetLanguages" => target_languages}} <- res.body do
      Enum.each(target_languages, fn target_language ->
        download_translation_for_language(workspace, client, project_id, file, target_language)
      end)
    end
  end

  def download_translation_for_language(workspace, client, project_id, file, target_language) do
    with {:ok, res} <- Crowdin.build_project_file_translation(client, project_id, file["id"], target_language["id"]),
         200 <- res.status,
         %{"data" => %{"url" => url}} <- res.body,
         {:ok, res} <- Tesla.get(url) do
      export_pattern = file["exportOptions"]["exportPattern"]
      target_file_name = translate_file_name(export_pattern, target_language)
      target_path = Path.join(workspace, target_file_name)
      File.mkdir_p(Path.dirname(target_path))
      File.write(target_path, res.body)
    end
  end

  def translate_file_name(export_pattern, target_language) do
    Enum.reduce(target_language, export_pattern, fn {key, value}, acc ->
      if is_binary(value) do
        key = key |> String.replace(~r/([A-Z])/, "_\\1") |> String.downcase()
        String.replace(acc, "%#{key}%", to_string(value))
      else
        acc
      end
    end)
  end

  def create_pr_if_changed(workspace) do
    File.cd!(workspace)

    localization_branch = "localization"
    github_actor = System.get_env("GITHUB_ACTOR") |> IO.inspect(label: :actor)
    github_token = System.get_env("GITHUB_TOKEN") |> IO.inspect(label: :github_token)
    github_repository = System.get_env("GITHUB_REPOSITORY")
    repo_url="https://#{github_actor}:#{github_token}@github.com/#{github_repository}.git"
    System.cmd("git", ["config", "--global", "user.email", "crowdin-elixir-action@kahoot.com"])
    System.cmd("git", ["config", "--global", "user.name", "Crowdin Elixir Action"])
    System.cmd("git", ["checkout", "-b", localization_branch])

    case System.cmd("git", ["status", "--porcelain", "--untracked-files=no"]) do
      {"", 0} ->
        :ok
      _ ->
        IO.puts "Push to branch #{localization_branch}"

        System.cmd("git", ["add", "."])
        System.cmd("git", ["commit", "-m", "Update localization"])
        System.cmd("git", ["push", "--force", repo_url]) |> IO.inspect(label: :push)
    end
  end

  defp sync(workspace, token, project_id, source_file) do
    IO.puts "Sync with crowdin"
    client = Crowdin.client(token)
    with {:ok, res} <- upload_source(workspace, client, project_id, source_file),
         file <- res.body["data"] do
      download_translation(workspace, client, project_id, file)
      create_pr_if_changed(workspace)
    end
  end
end