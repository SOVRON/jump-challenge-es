defmodule Jump.Web.HubspotSignatureValidator do
  @moduledoc """
  Validates HubSpot webhook signatures using X-HubSpot-Signature-v3.
  """

  @doc """
  Validates the HubSpot webhook signature.

  Returns true if the signature is valid, false otherwise.
  """
  def validate_signature(method, url, body, timestamp, signature, client_secret) do
    expected_signature = generate_signature(method, url, body, timestamp, client_secret)
    secure_compare(signature, expected_signature)
  end

  @doc """
  Checks if the timestamp is within acceptable range (within 5 minutes).
  """
  def valid_timestamp?(timestamp_unix) do
    current_time = System.system_time(:second)
    # Accept timestamps within 5 minutes (300 seconds)
    abs(current_time - timestamp_unix) <= 300
  end

  # Private functions

  defp generate_signature(method, url, body, timestamp_unix, client_secret) do
    timestamp = Integer.to_string(timestamp_unix)

    source_string =
      method <>
        " " <>
        url <>
        timestamp <>
        body

    :crypto.mac(:hmac, :sha256, client_secret, source_string)
    |> Base.encode64()
  end

  # Secure string comparison to prevent timing attacks
  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    :crypto.bytes_to_integer(:crypto.mac(:hmac, :sha256, <<>>, a)) ==
      :crypto.bytes_to_integer(:crypto.mac(:hmac, :sha256, <<>>, b))
  end

  defp secure_compare(_, _) do
    false
  end
end
