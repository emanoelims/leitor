defmodule Leitor.FigureEditorStub do
  @moduledoc false
  defdelegate review(model, prompt, images, schema, options), to: Leitor.FigureProgramStub

  def code_step(_model, context, _tools, options) do
    Process.put(:figure_editor_last_context, context)
    Process.put(:figure_editor_last_options, options)
    Process.put(:figure_editor_options, Process.get(:figure_editor_options, []) ++ [options])
    stage = Process.get(:figure_editor_stage, 0)
    Process.put(:figure_editor_stage, stage + 1)
    output_tokens = Map.get(Process.get(:figure_editor_output_tokens, %{}), stage, 100)

    {name, args} =
      case {Process.get(:figure_editor_script), stage} do
        {script, index} when is_list(script) -> Enum.at(script, index, {"finish", %{}})
        _ -> default_call(stage)
      end

    calls =
      case name do
        "truncated" -> []
        "truncated_tool" -> [ReqLLM.ToolCall.new("editor-#{stage}", "write_file", ~s({"path":"geometry.mjs","content":))]
        _ -> [ReqLLM.ToolCall.new("editor-#{stage}", name, Jason.encode!(args))]
      end

    {:ok,
     struct(ReqLLM.Response, %{
       id: "response-#{stage}",
       model: "stub",
       message: ReqLLM.Context.assistant("", tool_calls: calls),
       context: context,
       finish_reason: if(name in ["truncated", "truncated_tool"], do: :length, else: :tool_calls),
       usage: %{output_tokens: output_tokens, input_tokens: 100}
     })}
  end

  defp default_call(stage) do
    case stage do
      0 -> {"read_file", %{path: "geometry.mjs"}}
      1 -> {"patch_file", %{path: "geometry.mjs", old: "export const shape=1", new: "export const shape=2"}}
      2 -> {"render", %{}}
      _ -> {"finish", %{}}
    end
  end
end
