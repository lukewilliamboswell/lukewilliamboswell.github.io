app [main] { pf: platform "https://github.com/lukewilliamboswell/basic-ssg/releases/download/0.5.0/MlW8VJCTuOFrlKRiW9h-WPOv4_5FqTrqlZZOi5fMqdo.tar.br" }

import pf.SSG
import pf.Types exposing [Args]
import pf.Html exposing [link, script, footer, text, html, head, body, meta]
import pf.Html.Attributes exposing [attribute, class, src, name, id, charset, href, rel, content, lang]

main : Args -> Task {} _
main = \{ inputDir, outputDir } ->

    # get the path and url of markdown files in content directory
    files = SSG.files! inputDir

    # helper Task to process each file
    processFile = \{ path, relpath, url } ->

        inHtml = SSG.parseMarkdown! path

        outHtml = transformFileContent url inHtml

        SSG.writeFile { outputDir, relpath, content: outHtml }
    ## process each file
    Task.forEach! files processFile

pageData =
    Dict.empty {}
    |> Dict.insert "index.html" { title: "Luke Boswell", description: "Personal site for Luke Boswell" }
    |> Dict.insert "roc-htmx-demo/index.html" { title: "Roc+htmx Demo", description: "An early exploration of Roc+htmx" }

getPage : Str -> { title : Str, description : Str }
getPage = \current ->
    Dict.get pageData current
    |> Result.withDefault { title: "", description: "" }

getTitle : Str -> Str
getTitle = \current ->
    getPage current |> .title

getDescription : Str -> Str
getDescription = \current ->
    getPage current |> .description

transformFileContent : Str, Str -> Str
transformFileContent = \page, htmlContent ->
    Html.render (view page htmlContent)

view : Str, Str -> Html.Node
view = \page, htmlContent ->
    mainBody = [text htmlContent]

    bodyAttrs = [id "index-page"]

    html [lang "en", class "no-js"] [
        head [] [
            meta [charset "utf-8"],
            Html.title [] [text (getTitle page)],
            meta [name "description", content (getDescription page)],
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
        body bodyAttrs [
            Html.main [] mainBody,
            footer [] [],
        ],
    ]
