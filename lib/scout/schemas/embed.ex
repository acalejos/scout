defmodule Scout.Schemas.Embed do
  @moduledoc """
  Specification for embedded schemas.

  For embedded schemas:
  - Use embeds_one (cardinality: :one) for nested single objects
  - Use embeds_many (cardinality: :many) for nested lists of objects
  - Mark as required: true if the embed must be present
  """
  use Flint.Schema, extensions: Flint.default_extensions() ++ [Instructor.Instruction]
  alias Scout.Schemas.Field

  embedded_schema do
    field!(:field_name, :string, doc: "The name of the field in the schema.")
    field!(:module_name, :string, doc: "The name of the embedded module to create.")
    field!(:cardinality, Ecto.Enum, values: [:one, :many])
    field(:required, :boolean, default: false)

    field!(:description, :string,
      doc:
        "A description of the schema. Semantically describes the schema in general. Does not go into field-specific details."
    )

    embeds_many(:fields, Field)
    # embeds_many(:embeds, __MODULE__)
  end

  def generate(%__MODULE__{} = embed_spec) do
    name = embed_spec.field_name |> Macro.underscore() |> String.to_atom()
    module = embed_spec.module_name |> String.capitalize()
    module = Module.concat([module])

    case embed_spec.cardinality do
      :one ->
        if embed_spec.required do
          quote do
            embeds_one! unquote(name), unquote(module) do
              @moduledoc unquote(embed_spec.description)
              (unquote_splicing(Enum.map(embed_spec.fields, &Field.generate/1)))
              # unquote_splicing(Enum.map(embed_spec.embeds, &generate_embed/1))
            end
          end
        else
          quote do
            embeds_one unquote(name), unquote(module) do
              @moduledoc unquote(embed_spec.description)
              (unquote_splicing(Enum.map(embed_spec.fields, &Field.generate/1)))
              # unquote_splicing(Enum.map(embed_spec.embeds, &generate_embed/1))
            end
          end
        end

      :many ->
        if embed_spec.required do
          quote do
            embeds_many! unquote(name), unquote(module) do
              @moduledoc unquote(embed_spec.description)
              (unquote_splicing(Enum.map(embed_spec.fields, &Field.generate/1)))
              # unquote_splicing(Enum.map(embed_spec.embeds, &generate_embed/1))
            end
          end
        else
          quote do
            embeds_many unquote(name), unquote(module) do
              @moduledoc unquote(embed_spec.description)
              (unquote_splicing(Enum.map(embed_spec.fields, &Field.generate/1)))
              # unquote_splicing(Enum.map(embed_spec.embeds, &generate_embed/1))
            end
          end
        end
    end
  end
end
