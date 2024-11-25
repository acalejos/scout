defmodule Scout do
  def probe(source, opts \\ [])

  def probe(%URI{} = uri, opts) do
    req = Req.new(url: uri) |> Req.merge(Keyword.get(opts, :req_opts, []))

    with {:ok, %Req.Response{status: 200, headers: headers, body: body}} <-
           Req.get(req) do
      type =
        case headers do
          %{"content-type" => content_type} when is_list(content_type) ->
            Enum.join(content_type, " ")

          %{"content-type" => content_type} ->
            content_type

          _ ->
            "web page"
        end

      probe(body, [{:type, type} | opts])
    end
  end

  def probe(source, opts) when is_binary(source) do
    {prefix, opts} = Keyword.pop(opts, :prefix)

    {schema_module, opts} =
      Keyword.pop(
        opts,
        :schema_module,
        {Flint.Schema, extensions: Flint.default_extensions() ++ [Instructor.Instruction]}
      )

    {type, opts} = Keyword.pop(opts, :type, "webpage")
    {create_module, opts} = Keyword.pop(opts, :create_module, true)

    {:ok, spec} =
      Scout.Schemas.Schema.chat_completion([content: source, type: type], opts)

    module_name = [prefix, spec.module_name] |> Enum.filter(& &1) |> Module.concat()

    if create_module do
      quoted_schema = Scout.Schemas.Schema.generate(spec)

      using =
        case schema_module do
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

      quoted_body =
        quote do
          unquote(using)
          unquote(quoted_schema)
        end

      Module.create(module_name, quoted_body, Macro.Env.location(__ENV__))
    end

    %Scout.Report{spec: spec, raw: source, response_model: module_name}
  end

  def discover(source, opts \\ [])

  def discover(%Scout.Report{raw: content, response_model: module_name}, opts) do
    opts = Keyword.drop(opts, [:prefix, :schema_module, :type, :create_module])

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

    Instructor.chat_completion(opts)
  end

  def discover(%URI{} = uri, opts) do
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
      |> probe(opts)
      |> discover(opts)
    end
  end

  def discover(content, opts) do
    response_model =
      Keyword.get_lazy(opts, :response_model, fn ->
        %Scout.Report{response_model: module_name} = probe(content, opts)
        module_name
      end)

    discover(%Scout.Report{raw: content, response_model: response_model}, opts)
  end
end
