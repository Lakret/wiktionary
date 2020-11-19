defmodule WiktionaryWeb.PageLive do
  use WiktionaryWeb, :live_view

  alias Wiktionary.Parser

  @impl true
  def mount(_params, _session, socket) do
    state = %{
      word: "",
      definition: "",
      error_message: "",
      request_id: 0,
      language: "German",
      languages_map: %{}
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
        languages_map =
          Parser.parse_article(body)
          |> Enum.map(fn {language, article} ->
            {language, article}
          end)

        assign(socket, definition: body, languages_map: languages_map)
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
end
