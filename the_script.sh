#!/bin/bash


set -e
set -o pipefail
set -u
set -x


curl --version >/dev/stderr
jq --version >/dev/stderr
sort --version >/dev/stderr


offset_second="$1"
channel_list_json="$2"  # https://api.nicochannel.jp/fc/content_providers/channels

file "${channel_list_json}" >/dev/stderr

now_second=$(date '+%s');
limit_second=$((${now_second} + ${offset_second}));


# collect live

declare -A live_timestamp_code_row_map

while read -r channel_info; do
  fanclub_site_id="$(jq --raw-output '.id' <<<"${channel_info}")";
  domain="$(jq --raw-output '.domain' <<<"${channel_info}")";

  live_page_info="$(
    curl -sS \
      -H 'fc_use_device: null' \
      "https://api.nicochannel.jp/fc/fanclub_sites/${fanclub_site_id}/live_pages?page=1&live_type=2&per_page=1" | \
    jq '.data' \
  )";

  if [[ "${live_page_info}" != 'null' ]]; then
    live_list="$(jq '.video_pages.list' <<<"${live_page_info}")";

    if [[ "${live_list}" != '[]' ]]; then
      content_code="$(jq --raw-output '.[0].content_code' <<<"${live_list}")";

      echo "processing [${content_code}]" >/dev/stderr

      live_info="$(
        curl -sS \
          -H 'fc_use_device: null' \
          "https://api.nicochannel.jp/fc/video_pages/${content_code}" | \
        jq '.data.video_page' \
      )";

      live_scheduled_start_at="$(jq --raw-output '.live_scheduled_start_at' <<<"${live_info}")";

      video_allow_dvr_flg="$(jq --raw-output '.video.allow_dvr_flg' <<<"${live_info}")";
      [[ "${video_allow_dvr_flg}" == 'true' ]] && video_allow_dvr_flg='';

      video_convert_to_vod_flg="$(jq --raw-output '.video.convert_to_vod_flg' <<<"${live_info}")";
      [[ "${video_convert_to_vod_flg}" == 'true' ]] && video_convert_to_vod_flg='';

      live_scheduled_start_at_second=$(date --date="${live_scheduled_start_at}" '+%s');

      title="$(jq --raw-output '.title' <<<"${live_info}")";

      thumbnail_url="$(jq --raw-output '.thumbnail_url' <<<"${live_info}")";
      if [[ "${thumbnail_url}" != 'null' ]]; then
        thumbnail_element="<img alt=\"${title}\" src=\"${thumbnail_url}\" height=\"64px\">"
      else
        thumbnail_element='<i>no thumbnail</i>'
      fi;

      if [[ ${now_second} -le ${live_scheduled_start_at_second} ]]; then
        if [[ ${live_scheduled_start_at_second} -le ${limit_second} ]]; then
          key="${live_scheduled_start_at_second} ${content_code}"
          value="$(
            cat <<TABLE_ROW
						  <tr>
						    <td>${live_scheduled_start_at}</td>
						    <td>
						      <a href="${domain}/live/${content_code}">${content_code}</a>
						      <br>
						      ${thumbnail_element}
						      <br>
						      ${title}
						    </td>
						    <td>${video_allow_dvr_flg}</td>
						    <td>${video_convert_to_vod_flg}</td>
						  </tr>
						TABLE_ROW
          )"
          live_timestamp_code_row_map["${key}"]="${value}"

          echo -e '\t''collected' >/dev/stderr

          continue
        fi;
      fi;

      echo -e '\t''ignored' >/dev/stderr
    fi;
  fi;
done < <(<"${channel_list_json}" jq --compact-output '.data.content_providers | .[]')

echo "count of incoming live = ${#live_timestamp_code_row_map[@]}" >/dev/stderr


# sort live

declare -a live_timestamp_code_array

while read live_timestamp_code; do
  live_timestamp_code_array+=("${live_timestamp_code}")
done < <(
  for live_timestamp_code in "${!live_timestamp_code_row_map[@]}"; do
    echo "${live_timestamp_code}"
  done | \
  sort -k 1
)


# draw table

echo '<table>'

cat <<'TABLE_HEADER'
  <thead>
    <th>START (UTC)</th>
    <th>Thumbnail, URL & Title</th>
    <th>allow_dvr_flg</th>
    <th>convert_to_vod_flg</th>
  </thead>
TABLE_HEADER

for key in "${live_timestamp_code_array[@]}"; do
  echo "${live_timestamp_code_row_map["${key}"]}"
done

echo '</table>'
