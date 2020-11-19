defmodule Wiktionary.Parser do
  @type language :: String.t()

  @type accumulator :: any()
  @type reducer :: (accumulator(), Floki.html_tree() -> accumulator())

  def test_wiktionary_article() do
    url = "https://en.wiktionary.org/wiki/Angst"
    response = HTTPoison.get!(url)
    response.body
  end

  # tree = {"span", [{"class", "mw-headline"}, {"id", "German"}], ["German"]}
  # Parser.to_html(tree) |> IO.puts()
  @spec to_html(Floki.html_tree()) :: String.t()
  def to_html(html_tree)

  def to_html(tags) when is_list(tags) do
    Enum.map(tags, &to_html/1) |> Enum.join()
  end

  def to_html({tag, [], []}), do: "<#{tag}></#{tag}>"

  def to_html({tag, attributes, children}) do
    attributes =
      case attributes do
        [] ->
          ""

        _ ->
          attributes = Enum.map(attributes, &to_html_attribute/1) |> Enum.join(" ")
          " #{attributes}"
      end

    children = Enum.map(children, &to_html/1) |> Enum.join()

    "<#{tag}#{attributes}>#{children}</#{tag}>"
  end

  def to_html(text) when is_binary(text), do: text

  @doc false
  def to_html_attribute({name, value}) do
    ~s(#{name}="#{value}")
  end

  @type extract :: {kind, attribute, Floki.html_tree()}
  @type kind :: :language_section_start
  @type attribute :: String.t()

  @spec parse_article(article :: String.t()) :: %{language() => Floki.html_tree()}
  def parse_article(article) do
    {:ok, article} = Floki.parse_document(article)
    article_content = Floki.find(article, "div#mw-content-text")
    [{"div", _attrs, children}] = article_content

    {language_name, staged, language_blocks} =
      fold_children(children, {nil, [], nil}, fn elem, {language_name, staged, result} ->
        case elem do
          {"h2", _attrs, [{"span", span_attrs, [new_language_name]} | _rest]} ->
            if Enum.any?(span_attrs, fn attr -> attr == {"class", "mw-headline"} end) do
              case result do
                nil ->
                  {new_language_name, [elem], []}

                result when is_list(result) ->
                  {new_language_name, [], result ++ [{language_name, Enum.reverse(staged)}]}
              end
            else
              {language_name, [elem | staged], result}
            end

          _ ->
            {language_name, [elem | staged], result}
        end
      end)

    language_blocks = language_blocks ++ [{language_name, Enum.reverse(staged)}]

    language_blocks |> Enum.into(%{})
  end

  @spec language_section_start(Floki.html_tree()) :: extract() | nil
  def language_section_start(elem) do
    case elem do
      {"h2", _attrs, [{"span", span_attrs, [possible_language_name]} | _rest]} ->
        if Enum.any?(span_attrs, fn attr -> attr == {"class", "mw-headline"} end) do
          {:language_section_start, possible_language_name, elem}
        else
          nil
        end

      _ ->
        nil
    end
  end

  ## Helper

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
