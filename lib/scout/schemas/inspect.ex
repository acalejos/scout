# defimpl Inspect,
#   for: [Scout.Schemas.Schema, Scout.Schemas.Embed, Scout.Schemas.Field] do
#   import Inspect.Algebra

#   def inspect(%{__struct__: module} = obj, _opts) do
#     generated = module.generate(obj) |> Macro.to_string()

#     # Split the string into lines and join with explicit line breaks
#     generated
#     |> String.split("\n")
#     |> Enum.map(&string(&1))
#     |> Enum.intersperse(line())
#     |> concat()
#     |> group()
#     # Use a fixed indentation of 2 spaces instead of opts.indent
#     |> nest(2)
#   end
# end
