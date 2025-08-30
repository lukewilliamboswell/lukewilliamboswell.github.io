app [main!] { pf: platform "https://github.com/lukewilliamboswell/basic-ssg/releases/download/0.9.0/NLodHsSCfTRet3ssC6WUTJVelmrHTqy9YJo2EdnslgM.tar.br" }

import pf.SSG
import pf.Types exposing [Args]
import pf.Html exposing [link, script, footer, text, html, head, body, meta]
import pf.Html.Attributes exposing [attribute, class, src, name, id, charset, href, rel, content, lang]

main! : Args => Result {} _
main! = \{ input_dir, output_dir } ->

    # get the path and url of markdown files in content directory
    files = SSG.files!(input_dir)?

    # helper Task to process each file
    process_file! = \{ path, relpath, url } ->

        in_html = SSG.parse_markdown!(path)?

        out_html = transform_file_content(url, in_html)

        SSG.write_file!({ output_dir, relpath, content: out_html })

    ## process each file
    List.for_each_try!(files, process_file!)

page_data =
    Dict.empty {}
    |> Dict.insert "index.html" { title: "Luke Boswell", description: "Personal site for Luke Boswell" }
    |> Dict.insert "roc-htmx-demo/index.html" { title: "Roc+htmx Demo", description: "An early exploration of Roc+htmx" }

get_page : Str -> { title : Str, description : Str }
get_page = \current ->
    Dict.get page_data current
    |> Result.with_default { title: "", description: "" }

get_title : Str -> Str
get_title = \current ->
    get_page current |> .title

get_description : Str -> Str
get_description = \current ->
    get_page current |> .description

transform_file_content : Str, Str -> Str
transform_file_content = \page, html_content ->
    Html.render (view page html_content)

view : Str, Str -> Html.Node
view = \page, html_content ->
    main_body = [text html_content]

    body_attrs = [id "index-page"]

    html [lang "en", class "no-js"] [
        head [] [
            meta [charset "utf-8"],
            Html.title [] [text (get_title page)],
            meta [name "description", content (get_description page)],
            meta [name "viewport", content "width=device-width"],
            link [rel "stylesheet", href "/site.css"],

            # <!-- Google tag (gtag.js) -->
            script [
                (attribute "async") "",
                src "https://www.googletagmanager.com/gtag/js?id=G-WP50D6PVC3",
            ] [],
            script [] [
                text
                    """
                    window.dataLayer = window.dataLayer || [];
                    function gtag(){dataLayer.push(arguments);}
                    gtag('js', new Date());

                    gtag('config', 'G-WP50D6PVC3');
                    """
            ],
        ],
        body body_attrs [
            Html.main [] main_body,
            footer [] [],
        ],
    ]
