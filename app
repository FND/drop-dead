#!/usr/bin/env python3

from urllib.parse import parse_qs
from pathlib import Path
from os import path
from uuid import uuid4

import re
import os
import sys


TITLE = "Drop Dead"
MSG_PATTERN = re.compile(r"^/([a-f0-9-]+)$")

ROOT_DIR = path.dirname(path.realpath(__file__))
STORE_DIR = path.join(ROOT_DIR, "store")
TEMPLATE = "template.html"

TEMPLATE = path.abspath(path.join(ROOT_DIR, TEMPLATE))
with open(TEMPLATE) as fh:
    TEMPLATE = fh.read()

Path(STORE_DIR).mkdir(parents=True, exist_ok=True)


def dispatcher(environ, start_response):
    method = environ["REQUEST_METHOD"]
    uri = environ.get("PATH_INFO", "")

    # TODO: declarative routing (incl. reverse routing)
    if uri == "/":
        return handle_root(method, environ, start_response)
    msg_id = MSG_PATTERN.match(uri)
    if msg_id:
        msg_id = msg_id.group(1)
        return handle_message(method, msg_id, environ, start_response)

    return render("404 Not Found", {
        "prompt": "This page does not exist."
    }, environ, start_response)


def handle_root(method, environ, start_response):
    if method == "POST":
        return save_message(None, environ, start_response)

    if method == "GET":
        return render("200 OK", {
            "prompt": "Please leave a message after the tone.",
            "form_uri": "/",
            "author": "",
            "message": ""
        }, environ, start_response)

    start_response("405 Method Not Allowed", [])
    return [] # TODO: render error page


def handle_message(method, msg_id, environ, start_response):
    if method == "POST":
        return save_message(msg_id, environ, start_response)

    if method == "GET":
        try:
            author, msg = retrieve_message(msg_id)
        except FileNotFoundError:
            return render("404 Not Found", {
                "prompt": "Message `%s` does not exist." % msg_id
            }, environ, start_response)

        return render("200 OK", {
            "prompt": "Feel free to update your message.",
            "form_uri": "/%s" % msg_id,
            "author": author,
            "message": msg
        }, environ, start_response)

    start_response("405 Method Not Allowed", [])
    return [] # TODO: render error page


def render(status_line, params, environ, start_response):
    start_response(status_line, [("Content-Type", "text/html")])

    content = """
<h1>
    <a href="/">{title}</a>
</h1>
<p>{prompt}</p>
    """.format(title=TITLE, **params)

    if params.get("form_uri"):
        content += """
<form action="{form_uri}" method="post">
    <label>
        <span>Your name and/or contact details (optional)</span>
        <input name="author" value="{author}">
    </label>
    <label>
        <span>Your message</span>
        <textarea name="message">{message}</textarea>
    </label>
    <button>submit</button>
</form>
    """.format(**params)

    return [
        TEMPLATE.
            replace("%TITLE%", TITLE).
            replace("%BODY%", content).
            encode("utf-8")
    ]


def redirect(url, start_response):
    start_response("302 Found", [("Location", url)]) # XXX: 303?
    return []


def save_message(msg_id, environ, start_response):
    try:
        author, msg = parse_message(environ)
    except ValueError:
        return render("400 Bad Request", {
            "prompt": "Invalid request."
        }, environ, start_response)

    if msg_id is None or len(msg.strip()) or (author and len(author.strip()):
        msg_id = store_message(author, msg, msg_id)
        return redirect("/%s" % msg_id, start_response)

    delete_message(msg_id)
    return redirect("/drop-dead/", start_response)


def parse_message(environ):
    try:
        payload_size = int(environ.get("CONTENT_LENGTH", 0))
    except ValueError:
        payload_size = 0
    request_body = environ["wsgi.input"].read(payload_size).decode("utf-8")

    fields = parse_qs(request_body, strict_parsing=True)
    try:
        return fields.get("author", [None])[0], fields["message"][0]
    except (KeyError, IndexError):
        raise ValueError


def store_message(author, msg, msg_id=None):
    if author is None:
        author = ""

    if msg_id is None:
        msg_id = str(uuid4())
        mode = "x"
    else:
        mode = "w"

    msg_path = path.join(STORE_DIR, msg_id)
    try:
        with open(msg_path, mode=mode, encoding="utf-8") as fh:
            fh.write("author: %s\r\n\r\n%s" % (author, msg))
    except FileExistsError: # just to be safe; should never occur with UUIDs
        create_message(author, msg)
    return msg_id


def delete_message(msg_id):
    msg_path = path.join(STORE_DIR, msg_id)
    os.remove(msg_path)


def retrieve_message(msg_id):
    msg_path = path.join(STORE_DIR, msg_id)
    with open(msg_path, mode="r", encoding="utf-8") as fh:
        content = fh.read()

    author, _, *msg = content.splitlines()
    return author[8:], "\r\n".join(msg)


if __name__ == "__main__":
    from wsgiref.simple_server import make_server

    host = "localhost"
    port = 8080

    srv = make_server(host, port, dispatcher)
    print("→ http://%s:%s" % (host, port), file=sys.stderr)
    srv.serve_forever()
