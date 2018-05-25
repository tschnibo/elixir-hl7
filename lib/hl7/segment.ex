defmodule Hl7.Segment do
  @callback new(data_list :: list) :: new_struct :: term
  @callback to_list(segment :: term) :: data_list :: list

  defmacro __using__(opts) do
    field_list = Keyword.get(opts, :fields, [])
    field_count = field_list |> Enum.count()
    field_list_with_overflow = field_list ++ [{:_overflow, nil}]
    field_data = field_list_with_overflow |> Enum.map(fn {k, _} -> {k, nil} end)
    undefined_struct = Keyword.get(opts, :undefined_struct, false)
    field_map = field_list |> Enum.with_index |> Enum.reduce(%{}, fn({{f, _}, i}, acc) -> Map.put(acc, i, f) end)

    quote do

      @behaviour Hl7.Segment

      defstruct unquote(field_data)

      def new(data_list) when is_list(data_list) do
        if not unquote(undefined_struct) do
          data_fields =
            unquote(field_list_with_overflow)
            |> Hl7.Segment.overflow_zip(data_list)
            |> Enum.reduce(
              %__MODULE__{},
              fn {{field_name, field_type}, repeating_field_data}, result ->
                result
                |> Map.put(
                  field_name,
                  Hl7.Segment.new_repeating_field(repeating_field_data, field_type)
                )
              end
            )
        else
          [segment | tail] = data_list

          %__MODULE__{}
          |> Map.put(:segment, segment)
          |> Map.put(:values, tail)
        end
      end

      def get_part(%__MODULE__{} = data, field_name) when is_atom(field_name) do
        data |> Map.get(field_name, nil)
      end

      def get_part(%__MODULE__{} = data, i) when is_integer(i) and i < unquote(field_count) do
        f = get_field_map() |> Map.get(i, nil)
        data |> Map.get(f, nil)
      end

      def get_part(%__MODULE__{} = data, i) when is_integer(i) do
        overflow_index = i - unquote(field_count)
        overflow = data |> Map.get(:_overflow, []) |> Enum.at(overflow_index, nil)
      end

      def get_part(%__MODULE__{} = data, field_name) when is_binary(field_name) do
        data |> Map.get(String.to_existing_atom(field_name), nil)
      end

      def to_list(%__MODULE__{} = data) do
        if not unquote(undefined_struct) do
          Hl7.Segment.to_list(data, unquote(field_list_with_overflow), [])
        else
          [data.segment | data.values]
        end
      end

      defp get_field_map() do
        unquote(Macro.escape(field_map))
      end

    end
  end

  @doc false
  def new_repeating_field("", _field_type) do
    ""
  end

  def new_repeating_field(repeating_field_data, field_type) do
    repeating_field_data
    |> Enum.map(fn field_data -> new_field(field_data, field_type) end)
  end

  @doc false
  defp new_field(field_data, nil) do
    field_data
  end

  defp new_field("", _field_type) do
    ""
  end

  defp new_field(field_data, field_type) when is_binary(field_data) do
    apply(field_type, :new, [[field_data]])
  end

  defp new_field(field_data, field_type) when is_list(field_data) do
    apply(field_type, :new, [field_data])
  end

  @doc false
  def to_list(data, [{:_overflow, nil}], result) do
    data_value = Map.get(data, :_overflow)

    case data_value do
      nil -> Enum.reverse(result)
      "" -> ["" | result] |> Enum.reverse()
      _ -> Enum.reduce(data_value, result, fn d, acc -> [d | acc] end) |> Enum.reverse()
    end
  end

  def to_list(data, [{k, nil} | p_tail], result) do
    data_value = Map.get(data, k)

    case data_value do
      nil -> Enum.reverse(result)
      _ -> [data_value | to_list(data, p_tail, result)]
    end
  end

  def to_list(data, [{k, v} | p_tail], result) do
    data_value = Map.get(data, k)

    case data_value do
      nil ->
        Enum.reverse(result)

      text when is_binary(text) ->
        [text | to_list(data, p_tail, result)]

      _ ->
        [
          Enum.map(data_value, fn d -> to_data_type_list(v, d) end)
          | to_list(data, p_tail, result)
        ]
    end
  end

  def to_list(_data, [], result) do
    Enum.reverse(result)
  end

  @doc false
  def overflow_zip(field_list, data_list) do
    overflow_zip([], field_list, data_list) |> Enum.reverse()
  end

  def overflow_zip(result, _, []) do
    result
  end

  @doc false
  def overflow_zip(result, [{:_overflow, nil}], overflow_data) when is_list(overflow_data) do
    [{{:_overflow, nil}, overflow_data} | result]
  end

  def overflow_zip(result, [field | field_tail], [data | data_tail]) do
    new_result = [{field, data} | result]
    overflow_zip(new_result, field_tail, data_tail)
  end

  defp to_data_type_list(mod, d) do
    case d do
      "" -> ""
      _ -> apply(mod, :to_list, [d])
    end
  end
end
