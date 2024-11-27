defmodule Scout do
  @moduledoc """
  Scout is an AI-powered data extraction toolkit for Elixir.

  It uses AI to analyze web pages and text documents, automatically generating schema-based scrapers,
  making data extraction more efficient and maintainable.

  ## Features

  * Automatic schema generation from web pages and text documents
  * Support for multiple AI providers (OpenAI, Anthropic, Groq, etc.)
  * Type-safe data extraction
  * URL, raw HTML, and text document support
  * "Bring Your Own" (BYO) schema support for custom data extraction

  ## Examples

      # Generate and use a schema from a URL
      data = Scout.discover("https://example.com")

      # Generate a schema module without immediate extraction
      %Scout.Report{} = Scout.recon("https://example.com")

      # Use with custom configuration and a BYO schema
      custom_schema = %Scout.Schemas.Schema{...}
      Scout.discover("https://example.com",
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        response_model: custom_schema
      )
  """

  @error_regex ~r"%{(\w+)}"

  def module_from_spec(%Scout.Schemas.Schema{} = spec, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        schema_module:
          {Flint.Schema, extensions: Flint.default_extensions() ++ [Instructor.Instruction]}
      )

    quoted_schema = Scout.Schemas.Schema.generate(spec)

    using =
      case opts[:schema_module] do
        mod when is_atom(mod) ->
          quote do
            use unquote(mod)
          end

        {mod, args} when is_atom(mod) and is_list(args) ->
          quote do
            use unquote(mod), unquote(args)
          end

        _ ->
          raise ArgumentError,
                "`:schema_module` must either be atom() or an {atom(), keyword()}"
      end

    quote do
      @moduledoc unquote(spec.description)
      unquote(using)
      unquote(quoted_schema)
    end
  end

  def recon(source, opts \\ []) do
    source =
      with {:ok, uri} <- URI.new(source),
           req = Req.new(url: uri) |> Req.merge(Keyword.get(opts, :req_opts, [])),
           {:ok, %Req.Response{status: 200, body: body}} <- Req.get(req) do
        body
      else
        _ ->
          source
      end

    {module_opts, opts} = Keyword.split(opts, [:prefix, :schema_module])

    {type, opts} = Keyword.pop(opts, :type, "webpage")
    {create_module, opts} = Keyword.pop(opts, :create_module, true)

    case Scout.Schemas.Schema.chat_completion([content: source, type: type], opts) do
      {:ok, spec} ->
        if create_module do
          quoted_body = module_from_spec(spec, module_opts)
          Module.create(spec.module_name, quoted_body, Macro.Env.location(__ENV__))
        end

        %Scout.Report{spec: spec, raw: source, response_model: spec.module_name}

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(@error_regex, msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)

        {:error, message}
    end
  end

  def discover(source, opts \\ [])

  def discover(%Scout.Report{raw: content, response_model: module_name}, opts) do
    opts = Keyword.drop(opts, [:prefix, :schema_module, :type, :create_module])
    {config, opts} = Keyword.split(opts, [:api_key, :api_url, :http_options])

    messages =
      [
        %{
          role: "system",
          content: """
          You are a precision Schema Extraction Engine. Your singular purpose is to extract and structure data from any source content according to provided schemas with maximum accuracy.

          Core Function:
          Given source content and a schema, you identify and extract the requested data, converting it to the exact types specified in the schema. Nothing more, nothing less.
          """
        },
        %{role: "user", content: "Here is the content: #{inspect(content)}"}
      ]

    opts = opts ++ [response_model: module_name, messages: messages]

    Instructor.chat_completion(opts, config)
  end

  def discover(content, opts) do
    case URI.new(content) do
      {:ok, uri} ->
        if Keyword.get(opts, :response_model) do
          req = Req.new(url: uri) |> Req.merge(Keyword.get(opts, :req_opts, []))

          case Req.get(req) do
            {:ok, %Req.Response{status: 200, body: body}} ->
              discover(body, opts)

            error ->
              error
          end
        else
          uri
          |> recon(opts)
          |> discover(opts)
        end

      {:error, _} ->
        response_model =
          Keyword.get_lazy(opts, :response_model, fn ->
            %Scout.Report{response_model: module_name} = recon(content, opts)
            module_name
          end)

        discover(%Scout.Report{raw: content, response_model: response_model}, opts)
    end
  end
end
