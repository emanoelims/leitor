defmodule LeitorWeb.ReadingPreferences do
  @moduledoc false

  @choices %{
    "leading" => ~w(tight normal loose),
    "width" => ~w(narrow normal wide),
    "align" => ~w(left justify),
    "paras" => ~w(spaced indented),
    "pen" => ~w(vermilion cobalt moss graphite),
    "rail" => [true, false],
    "focus" => [true, false]
  }
  @defaults %{
    "leading" => "normal",
    "width" => "normal",
    "align" => "left",
    "paras" => "spaced",
    "pen" => "vermilion",
    "rail" => true,
    "focus" => false
  }

  def defaults, do: @defaults

  def normalize(params) when is_map(params) do
    Map.new(@defaults, fn {key, default} ->
      value = Map.get(params, key, default)
      {key, if(value in Map.fetch!(@choices, key), do: value, else: default)}
    end)
  end

  def normalize(_params), do: @defaults

  def change(preferences, key, value) do
    value =
      case {key, value} do
        {key, "true"} when key in ["rail", "focus"] -> true
        {key, "false"} when key in ["rail", "focus"] -> false
        _ -> value
      end

    case Map.fetch(@choices, key) do
      {:ok, choices} ->
        if value in choices, do: {:ok, Map.put(preferences, key, value)}, else: :error

      :error ->
        :error
    end
  end

  def reset_text(preferences), do: Map.merge(preferences, Map.take(@defaults, ~w(leading width align paras)))
end
