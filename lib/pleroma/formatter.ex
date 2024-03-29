# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Formatter do
  alias Pleroma.HTML
  alias Pleroma.User

  @any_mention_regex ~r/(?:^|\W)@\S+/
  @safe_mention_regex ~r/^\s*(?<mentions>(?:<[^>]+>\s*)*(?:@\S+\s+){1,})(?<rest>.*)/s
  @link_regex ~r"((?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~%:/?#[\]@!\$&'\(\)\*\+,;=.]+)|[0-9a-z+\-\.]+:[0-9a-z$-_.+!*'(),]+"ui
  @markdown_characters_regex ~r/(`|\*|_|{|}|[|]|\(|\)|#|\+|-|\.|!)/

  @default_markdown_options %Markdown.Renderer.Options{
    strikethrough: true,
    table: true,
    tasklist: true,
    footnotes: true,
    smart: true,
    unsafe_: true,
    autolink: true,
    akkoma_autolinks: true,
  }

  defp linkify_opts do
    Pleroma.Config.get(Pleroma.Formatter) ++
      [
        hashtag: true,
        hashtag_handler: &Pleroma.Formatter.hashtag_handler/4,
        mention: true,
        mention_handler: &Pleroma.Formatter.mention_handler/4
      ]
  end

  def escape_mention_handler("@" <> nickname = mention, buffer, _, _) do
    case User.get_cached_by_nickname(nickname) do
      %User{} ->
        # escape markdown characters with `\\`
        # (we don't want something like @user__name to be parsed by markdown)
        String.replace(mention, @markdown_characters_regex, "\\\\\\1")

      _ ->
        buffer
    end
  end

  def mention_tag(%User{id: id} = user, nickname, opts \\ []) do
    user_url = user.uri || user.ap_id
    nickname_text = get_nickname_text(nickname, opts)

    :span
    |> Phoenix.HTML.Tag.content_tag(
      Phoenix.HTML.Tag.content_tag(
        :a,
        ["@", Phoenix.HTML.Tag.content_tag(:span, nickname_text)],
        "data-user": id,
        class: "u-url mention",
        href: user_url,
        rel: "ugc"
      ),
      class: "h-card"
    )
    |> Phoenix.HTML.safe_to_string()
  end

  def mention_handler("@" <> nickname, buffer, opts, acc) do
    case User.get_cached_by_nickname(nickname) do
      %User{id: _id} = user ->
        link = mention_tag(user, nickname, opts)

        {link, %{acc | mentions: MapSet.put(acc.mentions, {"@" <> nickname, user})}}

      _ ->
        {buffer, acc}
    end
  end

  def hashtag_handler("#" <> tag = tag_text, _buffer, _opts, acc) do
    tag = String.downcase(tag)
    url = "#{Pleroma.Web.Endpoint.url()}/tag/#{tag}"

    link =
      Phoenix.HTML.Tag.content_tag(:a, tag_text,
        class: "hashtag",
        "data-tag": tag,
        href: url,
        rel: "tag ugc"
      )
      |> Phoenix.HTML.safe_to_string()

    {link, %{acc | tags: MapSet.put(acc.tags, {tag_text, tag})}}
  end

  @doc """
  Parses a text and replace plain text links with HTML. Returns a tuple with a result text, mentions, and hashtags.

  If the 'safe_mention' option is given, only consecutive mentions at the start the post are actually mentioned.
  """
  @spec linkify(String.t(), keyword()) ::
          {String.t(), [{String.t(), User.t()}], [{String.t(), String.t()}]}
  def linkify(text, options \\ []) do
    options = linkify_opts() ++ options

    if options[:safe_mention] && String.match?(text, @any_mention_regex) do
      %{"mentions" => mentions, "rest" => rest} = Regex.named_captures(@safe_mention_regex, text)
      acc = %{mentions: MapSet.new(), tags: MapSet.new()}

      {text_mentions, %{mentions: mentions}} = Linkify.link_map(mentions, acc, options)
      {text_rest, %{tags: tags}} = Linkify.link_map(rest, acc, options)

      {text_mentions <> text_rest, MapSet.to_list(mentions), MapSet.to_list(tags)}
    else
      acc = %{mentions: MapSet.new(), tags: MapSet.new()}
      {text, %{mentions: mentions, tags: tags}} = Linkify.link_map(text, acc, options)

      {text, MapSet.to_list(mentions), MapSet.to_list(tags)}
    end
  end

  @doc """
  Escapes a special characters in mention names.
  """
  def mentions_escape(text, options \\ []) do
    options =
      Keyword.merge(options,
        mention: true,
        url: false,
        mention_handler: &Pleroma.Formatter.escape_mention_handler/4
      )
    Linkify.link(text, options)
  end

  def markdown_to_html(text, opts \\ %{}) do
    Markdown.to_html(text, @default_markdown_options |> Map.merge(opts))
  end

  def html_escape({text, mentions, hashtags}, type) do
    {html_escape(text, type), mentions, hashtags}
  end

  def html_escape(text, "text/html") do
    HTML.filter_tags(text)
  end

  def html_escape(text, "text/x.misskeymarkdown") do
    text
    |> HTML.filter_tags()
  end

  def html_escape(text, "text/plain") do
    Regex.split(@link_regex, text, include_captures: true)
    |> Enum.map_every(2, fn chunk ->
      {:safe, part} = Phoenix.HTML.html_escape(chunk)
      part
    end)
    |> Enum.join("")
  end

  def truncate(text, max_length \\ 200, omission \\ "...") do
    # Remove trailing whitespace
    text = Regex.replace(~r/([^ \t\r\n])([ \t]+$)/u, text, "\\g{1}")

    if String.length(text) < max_length do
      text
    else
      length_with_omission = max_length - String.length(omission)
      String.slice(text, 0, length_with_omission) <> omission
    end
  end

  defp get_nickname_text(nickname, %{mentions_format: :full}), do: User.full_nickname(nickname)
  defp get_nickname_text(nickname, _), do: User.local_nickname(nickname)
end
