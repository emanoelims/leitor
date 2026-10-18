defmodule Leitor.AI.Vault do
  @moduledoc "Authenticated encryption for account provider keys, bound to their owner and provider."

  @doc "Encrypts a provider credential with a fresh nonce and owner-specific authenticated context."
  @spec encrypt(String.t(), Ecto.UUID.t(), String.t()) :: binary()
  def encrypt(plaintext, user_id, provider) do
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, plaintext, context(user_id, provider), 16, true)

    <<1, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>
  end

  @doc "Decrypts only authentic ciphertext for the given owner and provider; tampering returns an error."
  @spec decrypt(binary(), Ecto.UUID.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_credential}
  def decrypt(<<1, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>, user_id, provider) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, ciphertext, context(user_id, provider), tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :invalid_credential}
    end
  end

  def decrypt(_ciphertext, _user_id, _provider), do: {:error, :invalid_credential}

  defp key do
    endpoint = Application.fetch_env!(:leitor, LeitorWeb.Endpoint)
    secret = Application.get_env(:leitor, :ai_encryption_secret) || Keyword.fetch!(endpoint, :secret_key_base)
    :crypto.hash(:sha256, "leitor/account-ai-credentials/v1/" <> secret)
  end

  defp context(user_id, provider), do: "#{user_id}/#{provider}"
end
