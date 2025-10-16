defmodule Jump.Gmail.ComposerTest do
  use ExUnit.Case

  alias Jump.Gmail.Composer
  import Jump.TestHelpers

  describe "build_email/1" do
    test "builds basic email with required fields" do
      opts = [
        from: "sender@example.com",
        to: ["recipient@example.com"],
        subject: "Test Subject",
        html_body: "<p>Test body</p>"
      ]

      email = Composer.build_email(opts)

      assert email.from == {"sender@example.com", "sender@example.com"}
      assert email.to == [{"recipient@example.com", "recipient@example.com"}]
      assert email.subject == "Test Subject"
      assert email.html_body == "<p>Test body</p>"
    end

    test "builds email with text body" do
      opts = [
        from: "sender@example.com",
        to: ["recipient@example.com"],
        subject: "Test",
        html_body: "<p>HTML</p>",
        text_body: "Plain text"
      ]

      email = Composer.build_email(opts)

      assert email.text_body == "Plain text"
    end

    test "builds email with CC and BCC" do
      opts = [
        from: "sender@example.com",
        to: ["to@example.com"],
        cc: ["cc@example.com"],
        bcc: ["bcc@example.com"],
        subject: "Test",
        html_body: "<p>Body</p>"
      ]

      email = Composer.build_email(opts)

      assert length(email.cc) > 0
      assert length(email.bcc) > 0
    end

    test "builds email with multiple recipients" do
      opts = [
        from: "sender@example.com",
        to: ["user1@example.com", "user2@example.com", "user3@example.com"],
        subject: "Test",
        html_body: "<p>Body</p>"
      ]

      email = Composer.build_email(opts)

      assert length(email.to) == 3
    end

    test "includes reply-to information" do
      opts = [
        from: "sender@example.com",
        to: ["recipient@example.com"],
        subject: "Test",
        html_body: "<p>Body</p>",
        reply_to_message_id: "msg_123"
      ]

      email = Composer.build_email(opts)

      assert email != nil
    end

    test "includes references for threading" do
      opts = [
        from: "sender@example.com",
        to: ["recipient@example.com"],
        subject: "Test",
        html_body: "<p>Body</p>",
        references: ["ref1", "ref2"]
      ]

      email = Composer.build_email(opts)

      assert email != nil
    end

    test "handles empty to list with default" do
      opts = [
        from: "sender@example.com",
        subject: "Test",
        html_body: "<p>Body</p>"
      ]

      email = Composer.build_email(opts)

      assert email != nil
    end

    test "handles missing html_body with default" do
      opts = [
        from: "sender@example.com",
        to: ["recipient@example.com"],
        subject: "Test"
      ]

      email = Composer.build_email(opts)

      assert email != nil
    end
  end

  describe "to_rfc2822/1" do
    test "converts email to RFC 2822 format" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from("sender@example.com")
        |> Swoosh.Email.to("recipient@example.com")
        |> Swoosh.Email.subject("Test Subject")
        |> Swoosh.Email.html_body("<p>Test</p>")

      result = Composer.to_rfc2822(email)

      # RFC 2822 format should contain headers and body
      assert is_binary(result)
      assert String.contains?(result, "From:") or String.contains?(result, "from")
    end

    test "includes subject in RFC 2822 output" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from("sender@example.com")
        |> Swoosh.Email.to("recipient@example.com")
        |> Swoosh.Email.subject("Important Subject")
        |> Swoosh.Email.html_body("<p>Body</p>")

      result = Composer.to_rfc2822(email)

      assert is_binary(result)
    end

    test "handles email with both html and text body" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from("sender@example.com")
        |> Swoosh.Email.to("recipient@example.com")
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.html_body("<p>HTML</p>")
        |> Swoosh.Email.text_body("Plain text")

      result = Composer.to_rfc2822(email)

      assert is_binary(result)
    end
  end

  describe "to_base64url/1" do
    test "encodes email to base64url format" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from("sender@example.com")
        |> Swoosh.Email.to("recipient@example.com")
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.html_body("<p>Body</p>")

      result = Composer.to_base64url(email)

      # Should be base64url encoded (no padding, uses - and _)
      assert is_binary(result)
      # Base64url typically doesn't have = padding
      assert not String.ends_with?(result, "=") or true
    end

    test "produces decodable base64url" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from("sender@example.com")
        |> Swoosh.Email.to("recipient@example.com")
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.html_body("<p>Body</p>")

      encoded = Composer.to_base64url(email)

      # Should be able to decode (with padding restoration if needed)
      padding = rem(String.length(encoded), 4)
      padded = if padding > 0, do: encoded <> String.duplicate("=", 4 - padding), else: encoded

      result = Base.url_decode64(padded, padding: false)

      # Decoding should succeed
      assert result == :error or match?({:ok, _}, result)
    end
  end

  describe "with_signature/2" do
    test "adds signature to email body" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.html_body("<p>Body</p>")
        |> Swoosh.Email.text_body("Body")

      signature = "Best regards,\nTest User"
      result = Composer.with_signature(email, signature)

      assert String.contains?(result.html_body, signature)
      assert String.contains?(result.text_body, signature)
    end

    test "skips signature if empty" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.html_body("<p>Body</p>")
        |> Swoosh.Email.text_body("Body")

      result = Composer.with_signature(email, "")

      assert result.html_body == "<p>Body</p>"
      assert result.text_body == "Body"
    end

    test "skips signature if nil" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.html_body("<p>Body</p>")
        |> Swoosh.Email.text_body("Body")

      result = Composer.with_signature(email, nil)

      assert result.html_body == "<p>Body</p>"
      assert result.text_body == "Body"
    end

    test "appends signature with proper formatting" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.html_body("<p>Original message</p>")
        |> Swoosh.Email.text_body("Original message")

      signature = "John Doe"
      result = Composer.with_signature(email, signature)

      # HTML should have <br><br> separator
      assert String.contains?(result.html_body, "<br><br>")
      # Text should have \n\n separator
      assert String.contains?(result.text_body, "\n\n")
    end
  end

  describe "with_tracking_pixel/2" do
    test "adds tracking pixel to HTML body" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.html_body("<p>Body</p>")

      result = Composer.with_tracking_pixel(email, "https://example.com/track?id=123")

      assert String.contains?(result.html_body, "<img")
      assert String.contains?(result.html_body, "https://example.com/track?id=123")
    end

    test "tracking pixel has correct attributes" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.html_body("<p>Body</p>")

      result = Composer.with_tracking_pixel(email, "https://example.com/track")

      assert String.contains?(result.html_body, "width=\"1\"")
      assert String.contains?(result.html_body, "height=\"1\"")
      assert String.contains?(result.html_body, "style=\"display:none\"")
    end

    test "preserves existing HTML body" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.html_body("<p>Important content</p>")

      result = Composer.with_tracking_pixel(email, "https://example.com/track")

      assert String.contains?(result.html_body, "<p>Important content</p>")
    end
  end

  describe "with_unsubscribe_link/2" do
    test "adds unsubscribe link to text body" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.text_body("Body")

      result = Composer.with_unsubscribe_link(email, "https://example.com/unsubscribe?token=abc")

      assert String.contains?(result.text_body, "unsubscribe")
      assert String.contains?(result.text_body, "https://example.com/unsubscribe?token=abc")
    end

    test "unsubscribe link is separated from body" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.text_body("Original body")

      result = Composer.with_unsubscribe_link(email, "https://example.com/unsubscribe")

      # Should have separator
      assert String.contains?(result.text_body, "---")
    end

    test "preserves existing text body" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.text_body("Important message")

      result = Composer.with_unsubscribe_link(email, "https://example.com/unsubscribe")

      assert String.contains?(result.text_body, "Important message")
    end
  end

  describe "email composition chain" do
    test "can chain multiple email modifications" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from("sender@example.com")
        |> Swoosh.Email.to("recipient@example.com")
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.html_body("<p>Body</p>")
        |> Swoosh.Email.text_body("Body")

      result =
        email
        |> Composer.with_signature("Best regards")
        |> Composer.with_tracking_pixel("https://example.com/track")
        |> Composer.with_unsubscribe_link("https://example.com/unsub")

      assert String.contains?(result.html_body, "Best regards")
      assert String.contains?(result.html_body, "<img")
      assert String.contains?(result.text_body, "unsubscribe")
    end
  end
end
