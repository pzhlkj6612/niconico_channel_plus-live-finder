#!/bin/bash


set -e
set -o pipefail
set -u


curl --version >/dev/stderr
jq --version >/dev/stderr
sort --version >/dev/stderr


offset_second="$1"
channel_list_json="$2"

file "${channel_list_json}" >/dev/stderr

now_second=$(date '+%s');
limit_second=$((${now_second} + ${offset_second}));

echo '| START (UTC) | URL | ".video.allow_dvr_flg" | ".video.convert_to_vod_flg" |';
echo '| - |:- |:-:|:-:|';

<"${channel_list_json}" jq --compact-output '.data.content_providers | .[]' | \
  while read -r channel_info; do
    fanclub_site_id="$(jq --raw-output '.id' <<<"${channel_info}")";
    domain="$(jq --raw-output '.domain' <<<"${channel_info}")";

    live_page_info="$(
      curl -sS \
        -H 'fc_use_device: null' \
        "https://nfc-api.nicochannel.jp/fc/fanclub_sites/${fanclub_site_id}/live_pages?page=1&live_type=2&per_page=1" | \
      jq '.data' \
    )";

    if [[ "${live_page_info}" != 'null' ]]; then
      live_list="$(jq '.video_pages.list' <<<"${live_page_info}")";

      if [[ "${live_list}" != '[]' ]]; then
        content_code="$(jq --raw-output '.[0].content_code' <<<"${live_list}")";

        live_info="$(
          curl -sS \
            -H 'fc_use_device: null' \
            "https://nfc-api.nicochannel.jp/fc/video_pages/${content_code}" | \
          jq '.data.video_page' \
        )";

        live_scheduled_start_at="$(jq --raw-output '.live_scheduled_start_at' <<<"${live_info}")";

        video_allow_dvr_flg="$(jq --raw-output '.video.allow_dvr_flg' <<<"${live_info}")";
        [[ "${video_allow_dvr_flg}" == 'true' ]] && video_allow_dvr_flg='';

        video_convert_to_vod_flg="$(jq --raw-output '.video.convert_to_vod_flg' <<<"${live_info}")";
        [[ "${video_convert_to_vod_flg}" == 'true' ]] && video_convert_to_vod_flg='';

        live_scheduled_start_at_second=$(date --date="${live_scheduled_start_at}" '+%s');

        if [[ ${now_second} -le ${live_scheduled_start_at_second} ]]; then
          if [[ ${live_scheduled_start_at_second} -le ${limit_second} ]]; then
            echo "| ${live_scheduled_start_at} | [${content_code}](${domain}/live/${content_code}) | ${video_allow_dvr_flg} | ${video_convert_to_vod_flg} |";
          fi;
        fi;
      fi;
    fi;
  done | \
    sort;

