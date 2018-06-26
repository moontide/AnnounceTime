#!/bin/bash

#
# 利用百度语音免费接口 http://yuyin.baidu.com ，实现语音合成、语音识别功能
#
# 语音合成： 用其 http 接口，获得合成后的语音文件，缓存到本地，然后在 asterisk 中播放
# 语音识别： 用其 http 接口，将语音识别为文字，然后在 asterisk 控制台打印出来。
#            也许，还可以再调用语音合成，复述一遍
#

operation="$1"
param="${2%% }"
mac="$3"

BAIDU_VOICE_AVAILABLE_LANGUAGES_CODES=(zh ct en)
BAIDU_VOICE_AVAILABLE_LANGUAGES_NAMES=(普通话 粤语 英语)

BAIDU_VOICE_AVAILABLE_PERSONS_CODES=(0 1)
BAIDU_VOICE_AVAILABLE_PERSONS_NAMES=(女声 男声)

if [[ "$operation" == "tts" ]]
then
	if [[ ! -z "$param" && ! -z "$mac" ]]
	then
		echo "要进行语音合成的文字为： $param" >&2
		echo "MAC 地址参数： $mac" >&2

		language_code=${4:-zh}	# 语音合成目前只支持普通话
		speech_person_code=${5}
		volume=${6:-9}	# 默认最高音量
		pitch=${7}
		speed=${8}

		case "$language_code" in
			zh)
				language_name=${BAIDU_VOICE_AVAILABLE_LANGUAGES_NAMES[0]}
				;;
		#	ct)
		#		language_name=${BAIDU_VOICE_AVAILABLE_LANGUAGES_NAMES[1]}
		#		;;
		#	en)
		#		language_name=${BAIDU_VOICE_AVAILABLE_LANGUAGES_NAMES[2]}
		#		;;
		#	*)
		#		# 如果【语言代码】不指定或者写错代码，则从普通话、粤语中【随机】挑选一个语言播放
		#		#   * 不挑选英语
		#		#     -- 因为在 asterisk 中输入的都是汉字
		#		#   * 为什么选粤语
		#		#     -- 因为深圳、广州都位于广东省内……
		#		#rand=$(shuf -i 0-$((${#BAIDU_VOICE_AVAILABLE_LANGUAGES_CODES[*]} - 1)) -n 1)
		#		rand=$(shuf -i 0-1 -n 1)
		#		language_code=${BAIDU_VOICE_AVAILABLE_LANGUAGES_CODES[$rand]}
		#		language_name=${BAIDU_VOICE_AVAILABLE_LANGUAGES_NAMES[$rand]}
		#		;;
		esac

		case "$speech_person_code" in
			0)
				speech_person_name=${BAIDU_VOICE_AVAILABLE_PERSONS_NAMES[0]}
				;;
			1)
				speech_person_name=${BAIDU_VOICE_AVAILABLE_PERSONS_NAMES[1]}
				;;
			*)
				# 如果【发音人代码】不指定或者写错代码，则从音库中【随机】挑选一个人播放
				rand=$(shuf -i 0-$((${#BAIDU_VOICE_AVAILABLE_PERSONS_CODES[*]} - 1)) -n 1)
				speech_person_code=${BAIDU_VOICE_AVAILABLE_PERSONS_CODES[$rand]}
				speech_person_name=${BAIDU_VOICE_AVAILABLE_PERSONS_NAMES[$rand]}
				;;
		esac

		if [[ -z "$pitch" ]]
		then
			# 如果【音调】不指定，则从【4 到 6】中【随机】挑选一个音调播放
			rand=$(shuf -i 4-6 -n 1)
			pitch=$rand
		fi

		if [[ -z "$speed" ]]
		then
			# 如果【速度】不指定，则从【4 到 6】中【随机】挑选一个音调播放
			rand=$(shuf -i 4-6 -n 1)
			speed=$rand
		fi
	else
		echo "当第一个参数为 tts (语音合成)时，第二个参数需要给出要合成的文字；第三个参数给出 MAC 地址（接口调用需要）" >&2
		exit 2
	fi
elif [[ "$operation" == "asr" ]]
then
	if [[ -f "$param" && ! -z "$mac" ]]
	then
		echo "要进行语音识别的语音文件为： $param" >&2
		echo "MAC 地址参数： $mac" >&2
	else
		echo -e "当第一个参数为 asr (语音识别)时，第二个参数需要给出要识别的语音文件全路径，\e[31;1m语音格式必须是 8000赫兹、16位、单声道的 wav 文件\e[m；第三个参数给出 MAC 地址（接口调用需要）" >&2
		exit 2
	fi
else
	echo "第一个参数必须指定操作类型，操作类型取值有： tts asr 。 tts - 语音合成； asr - 语音识别" >&2
	exit 1
fi

BAIDU_TTS_API_URL=http://tsn.baidu.com/text2audio
BAIDU_ASR_API_URL=http://vop.baidu.com/server_api
BAIDU_ACCESS_TOKEN_URL=https://openapi.baidu.com/oauth/2.0/token
BAIDU_CLOUD_APP_KEY_FILE=/etc/asterisk/baidu-cloud-app-key.txt
BAIDU_CLOUD_APP_PASSWORD_FILE=/etc/asterisk/baidu-cloud-app-password.txt
token_data_file=/var/tmp/baidu-voice-api-access-token
baidu_voice_api_results_dir=/var/spool/asterisk/baidu-voice-api-results

if [[ -f "$BAIDU_CLOUD_APP_KEY_FILE" ]]
then
	baidu_cloud_app_key=$(cat "$BAIDU_CLOUD_APP_KEY_FILE")
else
	echo "百度应用程序的 key 文件 $BAIDU_CLOUD_APP_KEY_FILE 不存在，请将你的 app 的 key 放到 $BAIDU_CLOUD_APP_KEY_FILE 文件中" >&2
	exit 3
fi

if [[ -f "$BAIDU_CLOUD_APP_PASSWORD_FILE" ]]
then
	baidu_cloud_app_password=$(cat "$BAIDU_CLOUD_APP_PASSWORD_FILE")
else
	echo "百度应用程序的密码文件 $BAIDU_CLOUD_APP_PASSWORD_FILE 不存在，请将你的 app 的密码放到 $BAIDU_CLOUD_APP_PASSWORD_FILE 文件中" >&2
	exit 3
fi

which jq >&2
if [[ ! $? -eq 0 ]]
then
	echo "本脚本需要 jq 程序来解析 baidu api 返回的 json 数据，但看起来你没有安装 jq，请先安装后再试" >&2
	exit 3
fi

which sox >&2
IS_SOX_EXISTS=$?
which ffmpeg >&2
IS_FFMPEG_EXISTS=$?
if [[ ! $IS_SOX_EXISTS -eq 0 && ! $IS_FFMPEG_EXISTS -eq 0 ]]
then
	echo "本脚本需要 sox 或 ffmpeg 程序来将 baidu 语音合成返回的 mp3 文件转换成 ogg 格式，但看起来你没有安装 sox 或 ffmpeg，请先安装后再试" >&2
	exit 3
fi

function GetBaiduVoiceAPIAccessToken ()
{
	temp=$(cat "$token_data_file")
	if [[ ! -z "$temp" ]]
	then
		file_last_modification_time=$(stat -c %Y "$token_data_file")
		expire_duration=$(jq .expires_in "$token_data_file")
		baidu_voice_api_access_token=$(jq .access_token "$token_data_file")
		#baidu_voice_api_access_token=${baidu_voice_api_access_token:1:-1}	# 去掉 jq 返回结果的前后引号 # bash 4.1 不支持负数的 length
		baidu_voice_api_access_token=${baidu_voice_api_access_token//\"/}	# 去掉 jq 返回结果的前后引号
		echo "原 token   = [$baidu_voice_api_access_token]" >&2
		echo "原获取时间 = [$file_last_modification_time]" >&2
		echo "原有效时长 = [$expire_duration]" >&2
		echo "原过期时间 = [$(($file_last_modification_time + $expire_duration))]" >&2
		echo "  现在时间 = [$(date +%s)]" >&2

		if [[ $(date +%s) -ge $(($file_last_modification_time + $expire_duration)) ]]
		then
			echo -e "\e[36mtoken 貌似已经过期，需要获取新 token\e[m" >&2
		else
			echo -e "\e[36;1mtoken 未过期\e[m" >&2
			echo -n "$baidu_voice_api_access_token"
			return
		fi
	fi

	for ((i=1; i<=3; i++))
	do
		curl -d "grant_type=client_credentials&client_id=$baidu_cloud_app_key&client_secret=$baidu_cloud_app_password"  "$BAIDU_ACCESS_TOKEN_URL" > "$token_data_file"
		if [[ $? -eq 0 ]]
		then
			baidu_voice_api_access_token=$(jq .access_token "$token_data_file")
			baidu_voice_api_access_token=${baidu_voice_api_access_token//\"/}
			echo -e "\e[32;1m获取新 token 成功： [$baidu_voice_api_access_token]\e[m" >&2
			echo -n "$baidu_voice_api_access_token"
			return
		elif [[ $i -lt 3 ]]
		then
			echo -e "\e[31m获取新 token 失败，重试\e[m" >&2
		#elif [[ $i -ge 3 ]]
		else
			echo -e "\e[31m连续 3 次获取新 token 失败，退出\e[m" >&2
			exit 4
		fi
	done
}

baidu_voice_api_access_token=$(GetBaiduVoiceAPIAccessToken)

# ------------------
# 读取 /etc/profile.d/env.sh 配置
# 如果需要设置 curl 的 http 代理，请在此文件中设置
source /etc/profile.d/env.sh

# ------------------
# 先创建结果目录
mkdir -p "$baidu_voice_api_results_dir"


if [[ "$operation" == "tts" ]]
then
#-------------------------------------------------------------------------------
# 语音合成参数
#参数 	可需 	描述
#tex 	必填 	合成的文本，使用UTF-8编码，请注意文本长度必须小于1024字节
#lan 	必填 	语言选择,填写zh
#tok 	必填 	开放平台获取到的开发者 access_token
#ctp 	必填 	客户端类型选择，web端填写1
#cuid 	必填 	用户唯一标识，用来区分用户，填写机器 MAC 地址或 IMEI 码，长度为60以内
#
#spd 	选填 	语速，取值0-9，默认为5中语速
#pit 	选填 	音调，取值0-9，默认为5中语调
#vol 	选填 	音量，取值0-9，默认为5中音量
#per 	选填 	发音人选择，取值0-1, 0为女声，1为男声，默认为女声
#-------------------------------------------------------------------------------
	#url="$BAIDU_TTS_API_URL?lan=zh&per=$speetch_person&tok=$baidu_voice_api_access_token&ctp=1&cuid=$mac&tex=$param"

	output_file_without_ext_name="$baidu_voice_api_results_dir/tts-${language_name}-${speech_person_name}-音量${volume}-音调${pitch}-速度${speed}-$param"
	output_file="$output_file_without_ext_name.mp3"
	output_file_ogg="$output_file_without_ext_name.ogg"
	http_headers_output_file="$output_file_without_ext_name.headers.txt"

	if [[ -f "$output_file" ]]
	then
		file_type=$(file "$output_file")
		if [[ "$file_type" == *"MPEG ADTS, layer III"* ]]
		then
			tts_file_is_valid_mp3=true
			echo -e "\e[36m$output_file 已经存在，直接拿来用，不再重复语音合成操作\e[m" >&2
		else
			echo -e "\e[31m文件虽已存在，但文件内容不是 mp3 音频数据…\e[m" >&2
		fi
	fi

	if [[ "$tts_file_is_valid_mp3" != true ]]
	then
		curl -v --get\
			 --dump-header "$http_headers_output_file"\
			 --data-urlencode "tok=$baidu_voice_api_access_token"\
			 --data-urlencode "ctp=1"\
			 --data-urlencode "cuid=$mac"\
			 --data-urlencode "lan=$language_code"\
			 --data-urlencode "per=$speech_person_code"\
			 --data-urlencode "vol=$volume"\
			 --data-urlencode "pit=$pitch"\
			 --data-urlencode "spd=$speed"\
			 --data-urlencode "tex=$param"\
			 "$BAIDU_TTS_API_URL" > "$output_file"

		content_type_header=$(grep -i ^Content-Type "$http_headers_output_file")
		if [[ "$content_type_header" == *audio/* ]]
		then
			echo -e "\e[32;1m语音合成结果文件 $output_file\e[m" >&2
		else	# == *application/json*
			echo -e "\e[31m语音合成可能失败了: $content_type_header\e[m" >&2

			err_no=$(jq .err_no "$output_file")
			case $err_no in
				500)
					echo -e "\e[31m不支持输入\e[m" >&2
					;;
				501)
					echo -e "\e[31m输入参数不正确\e[m" >&2
					;;
				502)
					echo -e "\e[31mtoken验证失败\e[m" >&2
					;;
				503)
					echo -e "\e[31m合成后端错误\e[m" >&2
					;;
				*)
					echo -e "\e[31m$(jq .err_msg $output_file)\e[m" >&2
					;;
			esac

			#rm -f "$output_file"
			output_file_without_ext_name=
		fi
	fi
	echo -n "$output_file_without_ext_name"
#错误码解释
#错误码 	含义
#500 	不支持输入
#501 	输入参数不正确
#502 	token验证失败
#503 	合成后端错误


elif [[ "$operation" == "asr" ]]
then
#-------------------------------------------------------------------------------
# 语音识别参数
#
#    - 语音识别接口支持 POST 方式
#    - 目前 API 仅支持整段语音识别的模式，即需要上传整段语音进行识别
#    - 语音数据上传方式有两种：隐示发送和显示发送
#    - 原始语音的录音格式目前只支持评测 8k/16k 采样率 16bit 位深的单声道语音
#    - 压缩格式支持：pcm（不压缩）、wav、opus、speex、amr、x-flac
#    - 系统支持语言种类：中文（zh）、粤语（ct）、英文（en）
#    - 正式地址：http://vop.baidu.com/server_api
#
#隐示发送
#
#语音数据和其他参数通过标准 JSON 格式串行化 POST 上传， JSON 里包括的参数：
#字段名 	数据类型 	可需 	描述
#format 	sting 	必填 	语音压缩的格式，请填写上述格式之一，不区分大小写
#rate 	int 	必填 	采样率，支持 8000 或者 16000
#channel 	int 	必填 	声道数，仅支持单声道，请填写 1
#cuid 	string 	必填 	用户唯一标识，用来区分用户，填写机器 MAC 地址或 IMEI 码，长度为60以内
#token 	string 	必填 	开放平台获取到的开发者 access_token
#
#ptc 	int 	选填 	协议号，下行识别结果选择，默认 nbest 结果
#lan 	string 	选填 	语种选择，中文=zh、粤语=ct、英文=en，不区分大小写，默认中文
#url 	string 	选填 	语音下载地址
#callback 	string 	选填 	识别结果回调地址
#speech 	string 	选填 	真实的语音数据 ，需要进行base64 编码
#len 	int 	选填 	原始语音长度，单位字节
#
#
#
#
#
#显示发送
#
#语音数据直接放在 HTTP-BODY 中，控制参数以及相关统计信息通过 REST 参数传递，REST参数说明：
#字段名 	数据类型 	可需 	描述
#cuid 	string 	必填 	用户 ID，推荐使用设备mac 地址/手机IMEI 等设备唯一性参数
#token 	string 	必填 	开发者身份验证密钥
#lan 	string 	选填 	语种选择，中文=zh、粤语=ct、英文=en，不区分大小写，默认中文
#ptc 	int 	选填 	协议号，下行识别结果选择，默认 nbest 结果
#-------------------------------------------------------------------------------
	#
	# 用显示发送的方式发送语音数据
	#
	#url="$BAIDU_ASR_API_URL?format=wav&rate=8000&channel=1&tok=$baidu_voice_api_access_token&cuid=$mac"

	output_file="$baidu_voice_api_results_dir/asr-$(date +%s).json"
	curl -v \
		 --header "Content-Type: audio/wav;rate=8000"\
		 --data-binary "@$param"\
		 "$BAIDU_ASR_API_URL?channel=1&token=$baidu_voice_api_access_token&cuid=$mac" > "$output_file"

	echo "语音识别结果文件: $output_file" >&2
	cat "$output_file" >&2

	err_no=$(jq .err_no "$output_file")
	case $err_no in
		0)
			results=$(jq .result "$output_file")
			primary_result=$(jq .result[0] "$output_file")
			sn=$(jq .sn "$output_file")
			echo -e "\e[32;1m识别结果: $results\e[m" >&2
			echo "$primary_result"
			;;
		3300)
			echo -e "\e[31m输入参数不正确\e[m" >&2
			;;
		3301)
			echo -e "\e[31m识别错误\e[m" >&2
			;;
		3302)
			echo -e "\e[31m验证失败\e[m" >&2
			;;
		3303)
			echo -e "\e[31m语音服务器后端问题\e[m" >&2
			;;
		3304)
			echo -e "\e[31m请求 GPS 过大，超过限额\e[m" >&2
			;;
		3305)
			echo -e "\e[31m产品线当前日请求数超过限额\e[m" >&2
			;;
		*)
			echo -e "\e[31m$(jq .err_msg $output_file)\e[m" >&2
			;;
	esac

#错误码解释
#错误码 	含义
#3300 	输入参数不正确
#3301 	识别错误
#3302 	验证失败
#3303 	语音服务器后端问题
#3304 	请求 GPS 过大，超过限额
#3305 	产品线当前日请求数超过限额

fi

