defmodule WiktionaryWeb.PageLive do
  use WiktionaryWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    state = %{
      word: "",
      definition: "",
      error_message: "",
      request_id: 0,
      language: "German"
    }

    {:ok, assign(socket, state)}
  end

  @impl true
  def handle_event("update_word", %{"key" => _key, "value" => new_word}, socket) do
    request_id = socket.assigns.request_id + 1
    get_wiktionary_article_async(new_word, request_id)

    socket = assign(socket, word: new_word, request_id: request_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:definition, request_id, body}, socket) do
    socket =
      if socket.assigns.request_id == request_id do
        assign(socket, definition: body)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:definition_error, request_id, error_description}, socket) do
    socket =
      if socket.assigns.request_id == request_id do
        error_message =
          case error_description do
            {status_code, body} -> "Failed with status: #{status_code}, and body: #{body}."
            reason -> "Failed with reason: #{reason}."
          end

        assign(socket, error_message: error_message)
      else
        socket
      end

    {:noreply, socket}
  end

  ## Helpers

  @doc false
  def get_wiktionary_article_async(word, request_id)
      when is_binary(word) and is_integer(request_id) do
    pid = self()

    Task.start(fn ->
      url = "https://en.wiktionary.org/wiki/" <> word

      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
          send(pid, {:definition, request_id, body})

        {:ok, %HTTPoison.Response{body: body, status_code: status_code}} ->
          send(pid, {:definition_error, request_id, {status_code, body}})

        {:error, %HTTPoison.Error{reason: reason}} ->
          send(pid, {:definition_error, request_id, reason})
      end
    end)
  end

  @doc false
  def test_wiktionary_article() do
    url = "https://en.wiktionary.org/wiki/Angst"
    response = HTTPoison.get!(url)
    response.body
  end

  def parse_article(article) do
    {:ok, article} = Floki.parse_document(article)
    # Floki.find(article, "h2>span.mw-headline")
    article_content = Floki.find(article, "div#mw-content-text")
    [{"div", _attrs, children}] = article_content

    # TODO: add tree levels tracking to `fold_children`, and do tree reconstruction / extraction
    {language_name, staged, language_blocks} =
      fold_children(children, {nil, [], nil}, fn elem, {language_name, staged, result} = acc ->
        case elem do
          {"h2", _attrs, [{"span", span_attrs, [new_language_name]} | _rest]} ->
            if Enum.any?(span_attrs, fn attr -> attr == {"class", "mw-headline"} end) do
              case result do
                nil ->
                  {new_language_name, [elem], []}

                result when is_list(result) ->
                  {new_language_name, [],
                   result ++ [{:language_block, language_name, Enum.reverse(staged)}]}
              end
            else
              {language_name, [elem | staged], result}
            end

          _ ->
            {language_name, [elem | staged], result}
        end
      end)

    language_blocks = language_blocks ++ [{:language_block, language_name, Enum.reverse(staged)}]
  end

  def fold_children(children, acc, f) when is_list(children) do
    Enum.reduce(children, acc, fn elem, acc -> fold_children(elem, acc, f) end)
  end

  def fold_children({tag, attrs, children} = node, acc, f)
      when is_binary(tag) and is_list(attrs) do
    acc = f.(node, acc)
    fold_children(children, acc, f)
  end

  def fold_children(text, acc, f) when is_binary(text) do
    f.(text, acc)
  end

  def fold_children({:comment, _}, acc, f), do: acc
end
