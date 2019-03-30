#!/usr/bin/env bash

set -e
set -o pipefail

[[ -z "${DEBUG}" ]] || set -x

main() {
  local sub_command
  sub_command="$1"
  case "$sub_command" in
    sync)
      sync
      ;;
    stats)
      display_stats
      ;;
    posts-by-tag)
      tag="$2"
      posts_by_tag "${tag}"
      ;;
    *)
      print_usage_and_exit
      ;;
  esac
}

print_usage_and_exit() {
  cat <<HELP
usage: $0 <command>

Deep understanding of getpocket.com data

Commands:
 - sync
     synchronize data locally with what's on getpocket.com

 - stats
     displays some stats of the whole dataset

 - posts-by-tag <tag>
     lists the urls of articles associated with a tag
HELP

  exit 1
}

posts_by_tag() {
  local tag="$1"
  cat ~/.config/deep-pockets/data.json \
    | jq -r ".list[] | select(.tags != null) | select(.tags[].tag == \"${tag}\") | .given_url"
}

display_stats() {
  total_count=$(cat ~/.config/deep-pockets/data.json | jq .list[].item_id | wc -l)
  tagged_count=$(cat ~/.config/deep-pockets/data.json | jq -r '.list[] | select(.tags != null) | .item_id' | wc -l)
  unread_count=$(cat ~/.config/deep-pockets/data.json | jq -r '.list[] | select(.status == "0") | .item_id' | wc -l)
  favourited_count=$(cat ~/.config/deep-pockets/data.json | jq -r '.list[] | select(.favorite == "1") | .item_id' | wc -l)
  tag_counts=$(cat ~/.config/deep-pockets/data.json \
    | jq -r '.list[] | select(.tags != null) | .tags[].tag' \
    | sort \
    | uniq -c \
    | sort -nr)

  cat <<STATS
article count        : ${total_count}
articles unread      : ${unread_count}
articles tagged      : ${tagged_count}
articles favourited  : ${favourited_count}
tag counts           :
${tag_counts}
STATS

}

sync() {
  if [[ ! -d ~/.config/deep-pockets ]]; then
    mkdir -p ~/.config/deep-pockets
  fi

  # this jq query is an example of what makes the 1password CLI hard to work with
  # it is also coupling to my personal preference for a password manager
  CONSUMER_KEY=$(op get item "deep-pockets" | \
    jq -r '.details.sections[] |select(.fields)| .fields[] | select(.t == "consumer-key") | .v')

  # stub webserver to handle browser redirect from getpocket.com
  REDIRECT_URL="http://localhost:1500/"

  request_code=$(curl \
    https://getpocket.com/v3/oauth/request 2>/dev/null \
    -X POST \
    -H "Content-Type: application/json; charset=UTF-8" \
    -H "X-Accept: application/json" \
    -d @- <<JSON |
{
  "consumer_key":"${CONSUMER_KEY}",
  "redirect_uri":"${REDIRECT_URL}"
}
JSON
    jq -r .code)

  open "https://getpocket.com/auth/authorize?request_token=${request_code}&redirect_uri=${REDIRECT_URL}"

  nc -l localhost 1500 >/dev/null < <(echo -e "HTTP/1.1 200 OK\n\n $(date)")

  access_token=$(curl \
    https://getpocket.com/v3/oauth/authorize 2>/dev/null \
    -X POST \
    -H "Content-Type: application/json; charset=UTF-8" \
    -H "X-Accept: application/json" \
    -d @- <<JSON |
{
  "consumer_key":"${CONSUMER_KEY}",
  "code":"${request_code}"
}
JSON
    jq -r .access_token)


  # interesting thing about `read` is that it doesn't exit 0 when successful
  # so that's why the trailing `true`
  read -r -d '' req_json <<FOO ||
{
  "consumer_key":"${CONSUMER_KEY}",
  "access_token":"${access_token}",
  "state":"all",
  "detailType":"complete"
}
FOO
  true

  # There is 1 single endpoint for retrieval of date from pocket. Everything
  # you need to know is here: https://getpocket.com/developer/docs/v3/retrieve
  curl \
    https://getpocket.com/v3/get 2>/dev/null \
    -o ~/.config/deep-pockets/data.json \
    -X GET \
    -H "Content-Type: application/json" \
    -d "${req_json}"

  echo Data synchronized!
}

main "$@"