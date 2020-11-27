defmodule Wiktionary.Parser do
  alias Wiktionary.Parser.State

  @type language :: String.t()
  @type reducer :: (State.t(), Floki.html_tree() -> State.t())

  @type extract :: {:ok, attribute}
  @type attribute :: String.t()

  def test_wiktionary_article() do
    url = "https://en.wiktionary.org/wiki/wenn"
    response = HTTPoison.get!(url)
    response.body
  end

  @spec parse_article(article :: String.t()) :: map()
  def parse_article(article) do
    {:ok, article} = Floki.parse_document(article)
    article_content = Floki.find(article, "div#mw-content-text")
    [{"div", _attrs, children}] = article_content

    # NOTE: add your new extractors here to automatically apply them on parsing pass
    extractors = [
      {&language_section_start/1, &State.put_current_language/2},
      {&part_of_speech_section_start/1, &State.put_part_of_speech/2},
      {&word_defintions_section_start/1, &State.put_attribute(&1, :word, &2)},
      {&word_definitions/1, &State.put_attribute(&1, :definitions, &2)}
    ]

    state =
      fold_children(children, State.new(), fn elem, state ->
        Enum.reduce_while(extractors, state, fn {extractor, state_modifier}, state ->
          case extractor.(elem) do
            {:ok, extracted} ->
              state = state_modifier.(state, extracted)
              {:halt, state}

            nil ->
              {:cont, state}
          end
        end)
      end)

    State.finalize(state)
  end

  ## Extractors
  ## Note: add them in `extractors` list in `parse_article/1` to apply.

  @doc false
  @spec language_section_start(Floki.html_tree()) :: extract() | nil
  def language_section_start(elem) do
    case elem do
      # TODO: use id = language to extract them
      {"h2", _attrs, [{"span", span_attrs, [possible_language_name]} | _rest]} ->
        if {"class", "mw-headline"} in span_attrs do
          {:ok, possible_language_name}
        else
          nil
        end

      _ ->
        nil
    end
  end

  @parts_of_speech ~w(Noun Verb Adverb Adjective Pronoun Conjunction Interjection)

  @doc false
  @spec part_of_speech_section_start(Floki.html_tree()) :: extract() | nil
  def part_of_speech_section_start(elem) do
    case elem do
      {tag, _attrs, [{"span", span_attrs, [_possible_part_of_speech]} | _rest]}
      when tag in ["h3", "h4"] ->
        part_of_speech =
          Enum.find_value(span_attrs, fn
            {"id", id} ->
              Enum.find(@parts_of_speech, fn part_of_speech ->
                String.starts_with?(id, part_of_speech)
              end)

            _ ->
              nil
          end)

        if !is_nil(part_of_speech) do
          {:ok, part_of_speech}
        else
          nil
        end

      _ ->
        nil
    end
  end

  @word_defintion_section_start_classes ["Latinx headword", "Latn headword"]

  @doc false
  @spec word_defintions_section_start(Floki.html_tree()) :: extract() | nil
  def word_defintions_section_start(elem) do
    case elem do
      {"p", _attrs, [{"strong", strong_attrs, [word]} | _rest]} ->
        word? =
          Enum.find(strong_attrs, fn
            {"class", class} when class in @word_defintion_section_start_classes -> true
            _ -> false
          end)

        if word? do
          {:ok, word}
        else
          nil
        end

      _ ->
        nil
    end
  end

  @doc false
  @spec word_definitions(Floki.html_tree()) :: extract() | nil
  def word_definitions(elem) do
    case elem do
      {"ol", _attrs, children} when is_list(children) ->
        case Floki.find(elem, "li") do
          [] ->
            nil

          definitions ->
            definitions =
              Enum.map(definitions, fn definition ->
                # FIXME: for now we just remove examples for simplicity,
                # but we'll need to extract them in the future.
                definition = Floki.find_and_update(definition, "dl", fn _ -> :delete end)

                # FIXME: proper spacing around links (<a>)
                Floki.text(definition)
              end)

            {:ok, definitions}
        end

      _ ->
        nil
    end
  end

  ## Helpers

  @doc false
  @spec fold_children(Floki.html_tree(), State.t(), reducer()) :: State.t()
  def fold_children(html_tree, accumulator, reducer)

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

  def fold_children({:comment, _}, acc, _f), do: acc
end
