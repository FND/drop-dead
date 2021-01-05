#!/usr/bin/env python2
# coding=utf-8

from __future__ import print_function

from urlparse import parse_qs
from os import path
from uuid import uuid4

import re
import os
import sys


TITLE = u"Drop Dead"
MSG_PATTERN = re.compile(r"^/([a-f0-9-]+)$")

ROOT_DIR = path.dirname(path.realpath(__file__))
STORE_DIR = path.join(ROOT_DIR, "store")
TEMPLATE = "template.html"

TEMPLATE = path.abspath(path.join(ROOT_DIR, TEMPLATE))
with open(TEMPLATE) as fh:
    TEMPLATE = fh.read().decode("utf-8")

try:
    os.mkdir(STORE_DIR)
except OSError:
    pass


def dispatcher(environ, start_response):
    method = environ["REQUEST_METHOD"].decode("utf-8")
    uri = environ.get("PATH_INFO", "").decode("utf-8")

    # TODO: declarative routing (incl. reverse routing)
    if uri == "":
        start_response("301 Moved Permanently", [("Location", "/drop-dead/")])
        return []
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
            "form_uri": "/drop-dead/",
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
        except IOError:
            return render("404 Not Found", {
                "prompt": "Message `%s` does not exist." % msg_id
            }, environ, start_response)

        return render("200 OK", {
            "prompt": "Feel free to update your message.",
            "form_uri": "/drop-dead/%s" % msg_id,
            "author": author,
            "message": msg
        }, environ, start_response)

    start_response("405 Method Not Allowed", [])
    return [] # TODO: render error page


def render(status_line, params, environ, start_response):
    params = {}
    for k, v in params.items():
        k, v = [x.decode("utf-8") if isinstance(x, str) else x
                for x in (k, v)]
        params[k] = v

    start_response(status_line, [("Content-Type", "text/html")])

    content = u"""
<h1>
    <a href="/drop-dead/">{title}</a>
</h1>
<p>{prompt}</p>
    """.format(title=TITLE, **params)

    if params.get("form_uri"):
        content += u"""
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


def save_message(msg_id, environ, start_response):
    try:
        author, msg = parse_message(environ)
    except ValueError:
        return render("400 Bad Request", {
            "prompt": "Invalid request."
        }, environ, start_response)

    msg_id = store_message(author, msg, msg_id)
    start_response("302 Found", [("Location", "/drop-dead/%s" % str(msg_id))]) # XXX: 303?
    return []


def parse_message(environ):
    try:
        payload_size = int(environ.get("CONTENT_LENGTH", 0))
    except ValueError:
        payload_size = 0
    request_body = environ["wsgi.input"].read(payload_size)

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
        mode = "w" # FIXME: backport Python 3's `x` mode
    else:
        mode = "w"

    msg_path = path.join(STORE_DIR, msg_id)
    with open(msg_path, mode=mode) as fh:
        msg = "author: %s\r\n\r\n%s" % (author, msg)
        fh.write(msg)
    return msg_id


def retrieve_message(msg_id):
    msg_path = path.join(STORE_DIR, msg_id)
    with open(msg_path, mode="r") as fh:
        content = fh.read().decode("utf-8")

    parts = content.splitlines()
    author = parts[0]
    msg = parts[2:]
    return author[8:], "\r\n".join(msg)


if __name__ == "__main__":
    from wsgiref.simple_server import make_server

    host = "localhost"
    port = 8080

    srv = make_server(host, port, dispatcher)
    print("→ http://%s:%s" % (host, port), file=sys.stderr)
    srv.serve_forever()

application = dispatcher
