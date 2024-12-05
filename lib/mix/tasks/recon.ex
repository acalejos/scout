defmodule Mix.Tasks.Scout.Recon do
  @moduledoc """
  A Mix task for running Scout's recon functionality.

  This task allows you to run Scout with various configuration options including:

  - `--print` - Print the output to stdout (default: false)
  - `--out` - File path to write output to (.ex)
  - `--url` - URL to analyze
  - `--provider` - AI provider to use (openai, anthropic, groq, ollama, gemini) (default: "openai")
  - `--api-key` - API key for the selected provider
  - `--model` - Model to use for the selected provider
  - `--max-tokens` - Max tokens to allow in a request (Anthropic)

  ## Configuration

  The API key for your chosen provider can be configured in two ways:

  1. Command-line argument:
     ```
     --api-key "your-api-key"
     ```

  2. Environment variables (in order of precedence):
     - `SCOUT_TOKEN`
     - `{PROVIDER}_TOKEN` (e.g., `OPENAI_TOKEN`, `ANTHROPIC_TOKEN`)
     - `{PROVIDER}_API_KEY` (e.g., `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)

  ## Examples

      $ mix scout.recon --url "https://example.com" --provider openai --api-key "sk-..."
      $ mix scout.recon --url "https://example.com" --out "results.ex" --provider anthropic
  """
  @shortdoc "Analyzes web pages using AI to generate Elixir modules for web scraping"

  use Mix.Task

  @requirements ["app.start"]

  defp info(message) do
    Mix.shell().info(IO.ANSI.format([:yellow, "[INFO] ", message]))
  end

  defp error(message) do
    Mix.shell().error(IO.ANSI.format([:red, "[ERROR] ", message]))
  end

  defp success(message) do
    Mix.shell().info(IO.ANSI.format([:green, "[SUCCESS] ", message]))
  end

  defp to_existing_atom(string) when is_binary(string) do
    try do
      {:ok, String.to_existing_atom(string)}
    rescue
      ArgumentError ->
        {:error, :bad_atom}
    end
  end

  @impl Mix.Task
  def run(args) do
    Code.ensure_loaded!(Instructor.Union)

    {opts, _args, _} =
      OptionParser.parse(args,
        switches: [
          print: :boolean,
          out: :string,
          url: :string,
          provider: :string,
          api_key: :string,
          model: :string,
          create: :boolean,
          max_tokens: :integer
        ]
      )

    opts =
      Keyword.validate!(
        opts,
        [
          :out,
          :url,
          :api_key,
          :model,
          max_tokens: 4096,
          create: false,
          print: false,
          provider: "openai"
        ]
      )

    provider =
      case to_existing_atom(String.downcase(opts[:provider])) do
        {:ok, provider} ->
          provider

        {:error, _reason} ->
          error("Invalid provider `#{inspect(opts[:provider])}`")
          System.halt(1)
      end

    opts = Keyword.merge(opts, Application.get_env(:instructor, provider, []))

    adapter =
      case provider do
        :openai ->
          Instructor.Adapters.OpenAI

        :anthropic ->
          Instructor.Adapters.Anthropic

        :groq ->
          Instructor.Adapters.Groq

        :ollama ->
          Instructor.Adapters.Ollama

        :gemini ->
          Instructor.Adapters.Gemini

        :llamacpp ->
          Instructor.Adapters.Llamacpp

        :vllm ->
          Instructor.Adapters.VLLM

        bad ->
          error("Invalid provider `#{inspect(bad)}`")
          System.halt(1)
      end

    model =
      Keyword.get_lazy(opts, :model, fn ->
        default_model =
          case provider do
            :openai ->
              "gpt-4o-mini"

            :anthropic ->
              "claude-3-5-sonnet-latest"

            :gemini ->
              "gemini-1.5-flash"

            _ ->
              error("You must provide a model parameter with `--model`")
              System.halt(1)
          end

        info(
          "Using default model #{inspect(default_model)} for #{inspect(opts[:provider])} adapter"
        )

        default_model
      end)

    Application.put_env(:instructor, :adapter, adapter)

    api_key =
      opts[:api_key] ||
        System.get_env("SCOUT_TOKEN") ||
        System.get_env("#{String.upcase(opts[:provider])}_TOKEN") ||
        System.get_env("#{String.upcase(opts[:provider])}_API_KEY")

    if is_nil(api_key) do
      error("""
      You must provide an API key either explicitly using the `--api-key` argument,
      in the Instructor config, or as a system environment variable with one of the
      following names formats:
      * `SCOUT_TOKEN`
      * `{PROVIDER}_TOKEN`
      * `{PROVIDER}_API_KEY`
      """)

      System.halt(1)
    end

    if is_nil(opts[:url]) do
      error("You must provide a URL with `--url`!")
      System.halt(1)
    end

    info("Starting analysis for URL: #{opts[:url]}")

    report =
      ProgressBar.render_spinner(
        [
          frames: :braille,
          text: "Generating Schema…",
          done: [IO.ANSI.green(), "✓ Done", IO.ANSI.reset()],
          spinner_color: IO.ANSI.magenta()
        ],
        fn ->
          Scout.recon(opts[:url],
            api_key: api_key,
            model: model,
            create_module: opts[:create],
            max_tokens: opts[:max_tokens]
          )
        end
      )

    report =
      case report do
        %{spec: _spec} = result ->
          result

        {:error, reason} ->
          error(inspect(reason))
          System.halt(1)
      end

    quoted_body = Scout.module_from_spec(report.spec)

    quoted_module =
      quote do
        defmodule unquote(report.spec.module_name) do
          unquote(quoted_body)
        end
      end

    module_string =
      quoted_module
      # unescape Regex so they print pretty
      |> Macro.prewalk(fn
        {:%{}, [],
         [__struct__: Regex, opts: _opts, re_pattern: _rp, re_version: _rv, source: _src] = args} ->
          Enum.into(args, %{})

        node ->
          node
      end)
      |> Macro.to_string()

    if opts[:print] do
      Mix.shell().info(module_string)
    end

    if opts[:out] do
      case File.write(opts[:out], module_string) do
        :ok ->
          success("Module written to #{opts[:out]}")

        {:error, reason} ->
          error("Failed to write module to #{opts[:out]}: #{reason}")
      end
    end

    report
  end
end
