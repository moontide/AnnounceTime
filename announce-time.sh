#!/bin/bash
dir=$(dirname "$0")
cd "$dir"

# 报时前的提示音，类似商场广播前要先有提示音一样
#NOTIFY_SOUND_FILE=/usr/share/asterisk/sounds/beep.gsm
NOTIFY_SOUND_FILE=/usr/share/asterisk/sounds/beep.wav
#NOTIFY_SOUND_FILE=announce-time-notification.mp3
#today_sunrise_file=/tmp/today_sunrise.txt

path_f_sz121SunMoonRise="/var/log/sz121SunMoonRise"
mkdir -p "$path_f_sz121SunMoonRise"

function baidu_tts ()
{
	announcement="$1"
	#echo "announcement = $announcement" 2>&1
	/etc/asterisk/baidu-voice-api.sh "tts" "$announcement" "报时服务"
}

# 获取时间段的描述，比如：上午、中午、晌午、下午/过晌午、傍晚、黄昏、夜间、深夜、凌晨、清晨
# 传入的参数应该为按 HHMM 格式组成的 4 位数字，如： 1604 - 16点04分
# 参数1: 当前时间/指定时间
# 参数2: 日出时间
# 参数3: 日落时间
function GetTimeName ()
{
	tm="$1"
	sunrise="$2"
	sunset="$3"
echo "tm=$tm" >&2
echo "sunrise=$sunrise" >&2
echo "sunset=$sunset" >&2

	n_tm=$((10#$tm))
	#shopt -s extglob
	#n_sunrise=${sunrise##+(0)}	# https://askubuntu.com/questions/889744/what-is-the-purpose-of-shopt-s-extglob
	n_sunrise=$((10#$sunrise))
	if [[ $n_tm -ge 0 && $n_tm -lt 100 ]]; then
		time_name=半夜
	elif [[ $n_tm -ge 100 && $n_tm -lt $n_sunrise ]]; then
		time_name=凌晨
	elif [[ $n_tm -ge $n_sunrise && $n_tm -lt 830 ]]; then
		time_name=早上
	elif [[ $n_tm -ge 830 && $n_tm -lt 1130 ]]; then
		time_name=上午
	elif [[ $n_tm -ge 1130 && $n_tm -lt 1330 ]]; then
		time_name=中午
	elif [[ $n_tm -ge 1330 && $n_tm -lt 2359 ]]; then
		sunset_minute=$((10#${sunset:0:2} * 60 + 10#${sunset:2:2}))
		tm_minute=$((10#${tm:0:2} * 60 + 10#${tm:2:2}))
		diff_sunset=$(($sunset_minute - $tm_minute))
		if [[ $n_tm -gt 10#$sunset ]]; then
			time_name=晚上
		elif [[ $diff_sunset -lt 60 ]]; then
			time_name=傍晚
		else
			time_name=下午
		fi
	fi

	echo "$time_name"
}

# 获取深圳市当日的日出时间、日落时间，返回格式： HHMM 四位数字，第一行为日出时间，第二行为日落时间。
# 参数1：yyyy-MM-dd 格式的日期字符串
# 获取日落时间的目的：日出之前报时算作“凌晨”，日出及日出之后算作“早上”； 日落之前 1 小时报时算作“傍晚/黄昏”，日落及日落之后算作“晚上”
function GetShenZhenSunRiseSunSetInformation ()
{
	the_day_in_yyyy_MM_dd_format="$1"
	if [[ -z "$the_day_in_yyyy_MM_dd_format" ]]
	then
		echo "参数1：指定日期，格式：yyyy-MM-dd 格式的日期字符串"
		exit 4
	fi
	year=${the_day_in_yyyy_MM_dd_format:0:4}
	month=${the_day_in_yyyy_MM_dd_format:5:2}
	day=${the_day_in_yyyy_MM_dd_format//-/_}
	f_sz121SunMoonRise="sz121SunMoonRise_${year}_${month}.json"
	full_f_sz121SunMoonRise="$path_f_sz121SunMoonRise/$f_sz121SunMoonRise"
	if [[ ! -f "$full_f_sz121SunMoonRise" ]]
	then
		url_sz121SunMoonRise="https://weather.121.com.cn/data_cache/szWeather/SunMoonRise/$f_sz121SunMoonRise"
		echo "${url_sz121SunMoonRise}" >&2
		wget -o "$full_f_sz121SunMoonRise" -c --check-certificate=OFF "$url_sz121SunMoonRise" >&2
	fi

	json_key="D$day"
	# 返回数据格式： HH:MM，如： 19:11
	the_day_sunrise=$(jq -r ".${json_key}.data.sunRise" "$full_f_sz121SunMoonRise")
	the_day_sunset=$(jq -r ".${json_key}.data.sunSet" "$full_f_sz121SunMoonRise")
	the_day_moonrise=$(jq -r ".${json_key}.data.moonRise" "$full_f_sz121SunMoonRise")
	the_day_moonset=$(jq -r ".${json_key}.data.moonSet" "$full_f_sz121SunMoonRise")
	#echo "$the_day_sunset" > "$the_day_sunrise_file"

	# 将 HH:MM 中间的冒号去掉（变成 HHMM 格式），并输出
	echo "$the_day_in_yyyy_MM_dd_format" >&2
	echo "日出时间：${the_day_sunrise}" >&2
	echo "日落时间：${the_day_sunset}" >&2
	echo "月出时间：${the_day_moonrise}" >&2
	echo "月落时间：${the_day_moonset}" >&2
	the_day_sunrise_HHMM="${the_day_sunrise/:/}"
	the_day_sunset_HHMM="${the_day_sunset/:/}"
	echo -e "${the_day_sunrise_HHMM} ${the_day_sunset_HHMM} ${the_day_sunrise} ${the_day_sunset}"
}

function GetShenZhenWeatherInformation ()
{
	weather_json=$(curl -k "https://weather.121.com.cn/data_cache/szWeather/sz10day_new.json")
	today_report=$(echo "$weather_json" | jq -r ".today.report")
	echo "$today_report"
}

function announce_current_time_with_extra_information ()
{
	echo "--------------------------------------------------------------------------------"

	# 获取时间、时间描述
	hhmm_time=$(date +%H%M)
	hh=${hhmm_time:0:2}
	mm=${hhmm_time:2:2}
	time_for_tts=$(date +%I:%M)
	yesterday_sunrise_sunset_time_array=($(GetShenZhenSunRiseSunSetInformation "$(date +%F -d yesterday)"))
	yesterday_sunrise_time_HHMM="${yesterday_sunrise_sunset_time_array[0]}"
	yesterday_sunset_time_HHMM="${yesterday_sunrise_sunset_time_array[1]}"
	today_sunrise_sunset_time_array=($(GetShenZhenSunRiseSunSetInformation "$(date +%F)"))
	today_sunrise_time_HHMM="${today_sunrise_sunset_time_array[0]}"
	today_sunset_time_HHMM="${today_sunrise_sunset_time_array[1]}"
	today_sunrise_time="${today_sunrise_sunset_time_array[2]}"
	today_sunset_time="${today_sunrise_sunset_time_array[3]}"
echo "今天日出时间： $today_sunrise_time_HHMM"
echo "今天日落时间： $today_sunset_time_HHMM"

	sunset_difference_in_minutes=$(( (${today_sunset_time_HHMM:0:2}*60+${today_sunset_time_HHMM:2:2}) - (${yesterday_sunset_time_HHMM:0:2}*60+${yesterday_sunset_time_HHMM:2:2}) ))
	if [[ $sunset_difference_in_minutes -eq 0 ]]
	then
		sunset_difference_description="与昨天日落时间相同"
	elif [[ $sunset_difference_in_minutes -gt 0 ]]
	then
		sunset_difference_description="与昨天日落时间晚了 $sunset_difference_in_minutes 分钟；越来越接近夏至，天黑的越来越晚"
	elif [[ $sunset_difference_in_minutes -lt 0 ]]
	then
		sunset_difference_description="与昨天日落时间早了 ${sunset_difference_in_minutes#-} 分钟；越来越接近冬至，天黑的越来越早"
	fi

	time_name=$(GetTimeName "$hhmm_time" "$today_sunrise_time_HHMM" "$today_sunset_time_HHMM")
echo "时间名称： $time_name"

	# 生成要播报的文字
	#if [[ "$time_name" == "傍晚" ]]
	#then
		sunset_information_for_tts="今天日落时间为 $today_sunset_time ，$sunset_difference_description"
	#fi

	if [[ $mm == 00 ]]
	then
		announcement="$time_name $time_for_tts 整。$sunset_information_for_tts"
		if [[ $((10#$hh % 4 )) == 0 ]]	# 每 4 小时（小时数是 4 的倍数）播放天气信息
		then
			# 获取深圳气象台天气信息
			weather=$(GetShenZhenWeatherInformation)
			announcement="$announcement $weather"
		fi
	else
		announcement="$time_name $time_for_tts 。$sunset_information_for_tts"
	fi
echo "播报内容： $announcement"

	# 合成语音，并播放
	#tts_file=$(baidu_tts "$announcement")
	#tts_file=
	#tts_file="${tts_file}.mp3"	# 修正：因为 /etc/asterisk/baidu-voice-api.sh 是针对 asterisk 而写的：asterisk 在播放语音文件时，语音文件名不需要扩展名。所以，这里要补上扩展名
	#if [[ -f "$tts_file" ]]
	#then
	#	play "$NOTIFY_SOUND_FILE"
	#	play "$tts_file"
	#else
		#notify-send "播放报时音" "$tts_file 文件不存在"
		notify-send "$announcement"
	#fi
}

announce_current_time_with_extra_information
