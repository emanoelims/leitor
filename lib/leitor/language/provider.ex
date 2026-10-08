defmodule Leitor.Language.Provider do
  @moduledoc "Executes bounded ReqLLM structured requests without exposing provider credentials or errors to the UI."

  @doc "Generates and extracts a validated object; failures are mapped to recoverable categories."
  @spec generate(String.t(), String.t(), map()) :: Leitor.Language.result()
  def generate(model, prompt, schema) do
    if (ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")) in [nil, ""] do
      {:error, :unavailable}
    else
      case ReqLLM.model(%{provider: :anthropic, id: String.replace_prefix(model, "anthropic:", "")}) do
        {:ok, resolved} ->
          resolved
          |> ReqLLM.generate_object(prompt, schema, max_tokens: 6000, receive_timeout: 60_000)
          |> extract_object()

        {:error, _} ->
          {:error, :provider_error}
      end
    end
  end

  defp extract_object({:ok, response}) do
    case ReqLLM.Response.unwrap_object(response) do
      {:ok, object} when is_map(object) -> {:ok, Jason.decode!(Jason.encode!(object))}
      _ -> {:error, :invalid_response}
    end
  end

  defp extract_object({:error, _}), do: {:error, :provider_error}
end
