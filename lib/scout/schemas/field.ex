defmodule Scout.Schemas.Field do
  @moduledoc """
  Specification for individual fields in a schema

  Represents a regular field in an Ecto schema. You must do the following:
  - Use snake_case for field names
  - Choose appropriate types
  - Mark fields as required: true if they should not be nullable
  """
  use Flint.Schema, extensions: Flint.default_extensions() ++ [Instructor.Instruction]

  @base_types [
    :integer,
    :float,
    :boolean,
    :string,
    :map,
    :binary,
    :decimal,
    :id,
    :binary_id,
    :utc_datetime,
    :naive_datetime,
    :date,
    :time,
    :any,
    :utc_datetime_usec,
    :naive_datetime_usec,
    :time_usec
  ]

  embedded_schema do
    field!(:name, :string, map: name |> Macro.underscore() |> String.to_atom())

    field!(:base_type, Ecto.Enum,
      values: @base_types,
      doc: "The primitive type of the field. All fields must have a base type."
    )

    field(:composite, Ecto.Enum,
      values: [:array, :map, :none],
      doc:
        "Only include this for fields that are composite types, meaning they consist of one of more instances of the base type, either as an array or as a map."
    )

    field(:description, :string,
      doc:
        "A description of the field. This should be a description that would be useful when ingested by an LLM."
    )

    field(:required, :boolean, default: false)

    embeds_many(:validations, Validation) do
      field!(:key, Ecto.Enum,
        values: [
          :greater_than,
          :less_than,
          :less_than_or_equal_to,
          :greater_than_or_equal_to,
          :equal_to,
          :not_equal_to,
          :format,
          :subset_of,
          :in,
          :not_in,
          :is,
          :min,
          :max,
          :count
        ],
        doc:
          "The validation to use. All of these are functions from the `Ecto.Changeset.validate_` family of functions"
      ) do
        key in [
          :greater_than,
          :less_than,
          :less_than_or_equal_to,
          :greater_than_or_equal_to,
          :equal_to,
          :not_equal_to
        ] && (base_type not in [:integer, :float] || composite in [:array, :map]) ->
          "Validation #{key} only applies to fields with non-composite :integer and :float types."

        key in [:min, :max, :is] && (base_type != :string || composite != :array) ->
          "Validation #{key} only applies to fields that are either strings or arrays"

        key == :format && base_type != :string ->
          "Validation #{key} only applies to fields that are strings"
      end

      field!(:value, Union,
        oneof: [:integer, :float, :string, {:array, :any}],
        doc: """
        The value of the validation.

        Here are the types allowed according to validation:

        Float validations:
        * `:greater_than` - requires a float value
        * `:less_than` - requires a float value
        * `:less_than_or_equal_to` - requires a float value
        * `:greater_than_or_equal_to` - requires a float value
        * `:equal_to` - requires a float value
        * `:not_equal_to` - requires a float value

        Format validation:
        * `:format` - An Elixir regular expression that is a regex for the format (eg. fields such as phone numbers, URLs, emails, etc. should have a regex pattern here that represents them).

        List membership validations:
        * `:subset_of` - requires a list of valid values
        * `:in` - requires a list of valid values
        * `:not_in` - requires a list of valid values

        Count/length validations:
        * `:is` - requires an integer value
        * `:min` - requires an integer value
        * `:max` - requires an integer value
        * `:count` - requires an integer value
        """,
        derive: if(key == :format, do: &Regex.compile!/1, else: value)
      ) do
        key in [
          :greater_than,
          :less_than,
          :less_than_or_equal_to,
          :greater_than_or_equal_to,
          :equal_to,
          :not_equal_to
        ] && !is_number(value) ->
          "The value must be a float for validation `#{inspect(key)}`"

        key == :format && !is_binary(value) ->
          "When validation is `:format` you must return a binary representing an Elixir regular expression"

        key in [:subset_of, :in, :not_in] && !is_list(value) ->
          "The value must be a list for validation `#{inspect(key)}`"

        key in [:is, :min, :max, :count] && !is_integer(value) ->
          "The value must be an integer for validation `#{inspect(key)}"
      end
    end
  end

  def generate(%__MODULE__{} = field) do
    validations =
      field.validations
      |> Enum.into([], fn %{key: key, value: value} -> {key, Macro.escape(value)} end)

    validations = [{:doc, field.description} | validations]

    name = field.name

    type =
      case Map.get(field, :composite) do
        :array ->
          {:array, field.base_type}

        :map ->
          {:map, field.base_type}

        t when t in [nil, :none] ->
          field.base_type
      end

    opts =
      case validations do
        [] ->
          [name, type]

        _ ->
          [name, type, validations]
      end

    if field.required do
      quote do: field!(unquote_splicing(opts))
    else
      quote do: field(unquote_splicing(opts))
    end
  end
end
