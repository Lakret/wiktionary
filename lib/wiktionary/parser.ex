defmodule Wiktionary.Parser do
  @type language :: String.t()

  @type accumulator :: any()
  @type reducer :: (accumulator(), Floki.html_tree() -> accumulator())

  @type extract :: {kind, attribute, Floki.html_tree()}
  @type kind :: :language_section_start | :part_of_speech_section_start
  @type attribute :: String.t()

  def test_wiktionary_article() do
    url = "https://en.wiktionary.org/wiki/Angst"
    response = HTTPoison.get!(url)
    response.body
  end

  @spec parse_article(article :: String.t()) :: {language(), Floki.html_tree()}
  def parse_article(article) do
    {:ok, article} = Floki.parse_document(article)
    article_content = Floki.find(article, "div#mw-content-text")
    [{"div", _attrs, children}] = article_content

    # TODO: put subsections under corresponding language section
    # [{language, elems}, {language, elems}]
    # -> [{language, [{subsection, elems}]}, {language, ...}]
    {language_name, staged, language_blocks} =
      fold_children(children, {nil, [], nil}, fn elem, {language_name, staged, result} = acc ->
        case language_section_start(elem) do
          {:language_section_start, new_language_name, elem} ->
            add_to_acc(acc, :language, new_language_name, elem)

          nil ->
            case part_of_speech_section_start(elem) do
              {:part_of_speech_section_start, part_of_speech, elem} ->
                add_to_acc(acc, :part_of_speech, part_of_speech, elem)

              _ ->
                {language_name, [elem | staged], result}
            end
        end
      end)

    language_blocks ++ [{language_name, Enum.reverse(staged)}]
  end

  defp add_to_acc({prev_section_name, staged, result} = _acc, _section_kind, section_name, elem) do
    case result do
      nil ->
        {section_name, [elem], []}

      result when is_list(result) ->
        {section_name, [], result ++ [{prev_section_name, Enum.reverse(staged)}]}
    end
  end

  ## Helper

  @doc false
  @spec language_section_start(Floki.html_tree()) :: extract() | nil
  def language_section_start(elem) do
    case elem do
      # TODO: use id = language to extract them
      {"h2", _attrs, [{"span", span_attrs, [possible_language_name]} | _rest]} ->
        if {"class", "mw-headline"} in span_attrs do
          {:language_section_start, possible_language_name, elem}
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
        part_of_speech_or_nil =
          Enum.find_value(span_attrs, fn
            {"id", id} ->
              Enum.find(@parts_of_speech, fn part_of_speech ->
                String.starts_with?(id, part_of_speech)
              end)

            _ ->
              nil
          end)

        case part_of_speech_or_nil do
          nil ->
            nil

          part_of_speech ->
            {:part_of_speech_section_start, part_of_speech, elem}
        end

      _ ->
        nil
    end
  end

  @doc false
  @spec fold_children(Floki.html_tree(), accumulator(), reducer()) :: accumulator()
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
