#!/usr/bin/env bash
# modified by K.O. Bold
# * extended to have a chat history that can be picked up
# * fixed quit with multiline by adding escaped newlines in command reads; including fixof "-b | --big-prompt parameter (removed --multi-line-prompt)
# * extend to echo model at fhe beginning and to select model by call name (using $0)
# * added mdcat in addition to glow because mdcat is much faster. Kept glow as fallback
# * link https://github.com/swsnr/mdcat
# * added ability to change models
# * added comands and parameters for recalling a chat
# * added newchat command
# * added review chat commands


GLOBIGNORE="*"

CHAT_INIT_PROMPT="You are ChatGPT, a Large Language Model trained by OpenAI. You will be answering questions from users. You answer as concisely as possible for each response (e.g. don’t be verbose). If you are generating a list, do not have too many items. Keep the number of items short. Before each user prompt you will be given the chat history in Q&A form. Output your answer directly, with no labels in front. Do not start your answers with A or Anwser. You were trained on data up until 2021. Today's date is $(date +%m/%d/%Y)"

SYSTEM_PROMPT="You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible. Current date: $(date +%m/%d/%Y). Knowledge cutoff: 9/1/2021."

COMMAND_GENERATION_PROMPT="You are a Command Line Interface expert and your task is to provide functioning shell commands. Return a CLI command and nothing else - do not send it in a code block, quotes, or anything else, just the pure text CONTAINING ONLY THE COMMAND. If possible, return a one-line bash command or chain many commands together. Return ONLY the command ready to run in the terminal. The command should do the following:"

CHATGPT_CYAN_LABEL="\033[36mchatgpt \033[0m"
PROCESSING_LABEL="\n\033[90mProcessing... \033[0m\033[0K\r"
OVERWRITE_PROCESSING_LINE="             \033[0K\r"

#variables
FOLD=false
RECALL_A_CHAT=false
DEBUG_CALLS=false
MD_INTERPRETATION=true
SAVE_HISTORY=true
SHOW_INTERMEDIATE_COST=true
TOTAL_COST_MICROCENT=0


if [[ -z "$OPENAI_KEY" ]]; then
	echo "You need to set your OPENAI_KEY to use this script"
	echo "You can set it temporarily by running this on your terminal: export OPENAI_KEY=YOUR_KEY_HERE"
	exit 1
fi

parameterhelp() {
    cat <<EOF
Options:
  -i, --init-prompt          Provide initial chat prompt to use in context

  --init-prompt-from-file    Provide initial prompt from file

  -p, --prompt               Provide prompt instead of starting chat

  --prompt-from-file         Provide prompt from file

  -b, --big-prompt           Allow multi-line prompts during chat mode

  -t, --temperature          Temperature

  --max-tokens               Max number of tokens

  -l, --list                 List available openAI models

  -m, --model                Model to use
  
  -r, --recall               List of chats that can be recalled to continue

  -s, --size                 Image size. (The sizes that are accepted by the
                             OpenAI API are 256x256, 512x512, 1024x1024)
  -n | --numimages           Number of images to be generated.
                             (OpenAI supports 1-10; default 1)

  -c, --chat-context        For models that do not support chat context by
                             default (all models except gpt-3.5-turbo and
                             gpt-4), you can enable chat context, for the
                             model to remember your previous questions and
                             its previous answers. It also makes models
                             aware of todays date and what data it was trained
                             on.

  -d, --debug                always echo JSON communication to openai (input 
                             and output; only gpt-models/chat)
  --md-only                  Output clean markdown, do not use mdcat or glow
  --fold					 Wrap output in given number of colums
  --nh                       No history - don't save any history data
  --no-call-cost             Do not show cost information per call
EOF
}

commandhelp() {
		cat <<EOF
Commands:
  help           Display this help message
  h              [short]
  image: -       To generate images, start a prompt with image: If you are 
                 using iTerm, you can view the image directly in the
                 terminal. Otherwise the script will ask to open the image in
                 your browser.
  history -      To view your chat history
  recall -       To recall a previous chat (only shows last 10)
  rc             [short]
  rc:n           [recall chat n]
  recallfull -   To recall a previous chat (shows all with less)
  rcf            [short]
  cm -           To change model to the another gpt-model without changing 
                 the chat context
  cm:model -     To change to model directly
  cm4 -          To quickly change to GPT-4
  cm3 -          To quickly change to GPT-3.5-Turbo
  review -       To review the current chat
  rv             [short]
  reviewshort -  To review the current chat with truncated messages
  rs             [short]
  redisplaychat- To reset the display and redisplay chat in interactive style
  rd             [short]
  truncate -     To truncate the current chat
  tr             [short]
  newchat -      To start a new chat
  nc             [short]
  md -           Toggle "md-only" option to output clean markdown or us mdcat
  				 or glow
  models -       To get a list of the models available at OpenAI API
  model: -       To view all the information on a specific model, start a 
                 prompt with model: and the model id as it appears in the 
                 list of models. For example: "model:text-babbage:001" will 
                 get you all the fields for text-babbage:001 model
  command: -     To get a command with the specified functionality and run 
                 it, just type "command:" and explain what you want to 
                 achieve. The script will always ask you if you want to 
                 execute the command. i.e. 
        	    	"command:show me all files in this directory that have 
                    more than 150 lines of code" 
                 * If a command modifies your file system or dowloads 
                 external files the script tries to show a warning before
                 executing.
EOF
}

usage() {
	cat <<EOF
A simple, lightweight shell script to use OpenAI's Language Models and DALL-E from the terminal without installing Python or Node.js. Open Source and written in 100% Shell (Bash) 

https://github.com/0xacx/chatGPT-shell-cli/

By default the script uses the "gpt-3.5-turbo" model. if called through a link ending in "4" it defaults to use "gpt-4".
Note that "gpt-4" is about 10x more expensive. Prices per 1K tokens (as of 9/1/2023) are:
Model/context       	Input     Output
GPT-4 Turbo         	$0.0100   $0.0300	(gpt-4-1106-preview)
GPT-4V Turbo       		$0.0100   $0.0300	(gpt-4-vision-preview, gpt-4-1106-vision-preview = 85 tokens + 170 tokens per 512x512 tile)
GPT-4               	$0.0300   $0.0600	(gpt-4)
GPT-4 32K 	        	$0.0600   $0.1200	(gpt-4-32K)
GPT-3.5-Turbo	   		$0.0010   $0.0020	(gpt-3.5-turbo-1106, gpt-3.5-turbo, gpt-3.5-turbo-0301)
GPT-3.5-Turbo-Instruct	$0.0015   $0.0020	(gpt-3.5-turbo-instruct-0914, gpt-3.5-turbo-instruct)
GPT-3.5-Turbo 16K   	$0.0030   $0.0040	(gpt-3.5-turbo-16k-0613, gpt-3.5-turbo-16k)
Ada                 	$0.0004   $0.0004
Babbage             	$0.0005   $0.0005
Curie               	$0.0020   $0.0020
Davinci             	$0.0200   $0.0200
EOF
cat <<EOF > /dev/null
For image generation it is
Resolution   Price
1024×1024    $0.020 / image
512×512      $0.018 / image
256×256      $0.016 / image
EOF
commandhelp
parameterhelp
}

# error handling function
# $1 should be the response body
handle_error() {
	if echo "$1" | jq -e '.error' >/dev/null; then
		echo -e "Your request to Open AI API failed: \033[0;31m$(echo "$1" | jq -r '.error.type')\033[0m"
		echo "$1" | jq -r '.error.message'
		exit 1
	fi
}

# Function to prompt for a filename and handle overwriting
# three arguments ...  a name element ... number of files ... a string array for the filenames
prompt_filename() {
	nameelem=$1
	num=$2
	local -n filenames=$3
	datetime=$(date +"%Y%m%d-%H%M")
	default_filename="$HOME/${datetime}-IMG-${nameelem}.png"
	echo "Please enter a name for the picture(s)"
	echo "(For multiple pictures a counter will be added as _n before "".png"" : "
	read -p "[$default_filename]:" filename
	# Use the default filename if no input was provided
	filename="${filename:-$default_filename}"
	if [[ ! $filename == *.* ]] ; then
		filename="${filename}.png"
	fi
	fbase="${filename%.*}"
	fext="${filename##*.}"
	
	if [ ! "$fext"=="png" ] ; then
		filename="${filename}.png"
		fbase="${filename%.*}"
		fext="${filename##*.}"
	fi

	file_exists=false
	if (( num==1 )) ; then
		i=0
		filenames[$i]="$filename"
		if [[ -e "${filenames[i]}" ]] ; then
			file_exists=true
			echo "The file '${filenames[i]}' already exists."
		fi
	else
		for ((i = 0; i < num; i++)); do
			iform=$(printf "%02d" $i)
			filenames[$i]="${fbase}_${iform}.${fext}"
		done
		for ((i = 0; i < num; i++)); do
			if [[ -e "${filenames[i]}" ]]; then
				file_exists=true
				echo "The file '${filenames[i]}' already exists."
			fi
		done
	fi
	if $file_exists ; then
		read -p "Do you want to overwrite it? [y/N]: " overwrite
		if [[ $overwrite =~ ^[Yy]$ ]]; then
			return 0  # User confirmed overwriting
		else
			return 1  # User wants to enter a new filename
		fi
	fi
	return 0  # File doesn't exist
}

# calculate and store last call cost
#accounting $1 input tokens $2 output tokens
add_cost() {
	numi=$1
	numo=$2
	pi=0
	po=0
	case "$OPENAI_MODEL" in
		gpt-3.5-turbo-0301 | gpt-3.5-turbo-0613 | gpt-3.5-turbo-1106 | gpt-3.5-turbo )
		pi=10
		po=20
		;;
        gpt-3.5-turbo-instruct-0914 | gpt-3.5-turbo-instruct )
		pi=15
		po=20
		;;
		gpt-3.5-turbo-16k-0613 | gpt-3.5-turbo-16k )
		pi=30
		po=40
		;;
        gpt-4-1106-preview )
        pi=10
		po=30
        ;;
		gpt-4-0314 | gpt-4-0613 | gpt-4 )
		pi=300
		po=600
		;;
		ada | ada-code-search-code | ada-code-search-text | ada-search-document | ada-search-query | ada-similarity | code-search-ada-code-001 | code-search-ada-text-001 | text-ada-001 | text-embedding-ada-002 | text-search-ada-doc-001 | text-search-ada-query-001 | text-similarity-ada-001 )
		pi=4
		po=4
		;;
		curie | curie-instruct-beta | curie-search-document | curie-search-query | curie-similarity | text-curie-001 | text-search-curie-doc-001 | text-search-curie-query-001 | text-similarity-curie-001 )
		pi=20
		po=20
		;;
		babbage-002 | babbage | babbage-code-search-code | babbage-code-search-text | babbage-search-document | babbage-search-query | babbage-similarity | code-search-babbage-code-001 | code-search-babbage-text-001 | text-babbage-001 | text-search-babbage-doc-001 | text-search-babbage-query-001 | text-similarity-babbage-001 )
		pi=5
		po=5
		;;
		code-davinci-edit-001 | davinci-002 | davinci | davinci-instruct-beta | davinci-search-document | davinci-search-query | davinci-similarity | text-davinci-001 | text-davinci-002 | text-davinci-003 | text-davinci-edit-001 | text-search-davinci-doc-001 | text-search-davinci-query-001 | text-similarity-davinci-001 )
		pi=200
		po=200
		;;
		*)
		echo -n -e "\033[31m\033[1mERROR - No pricing information for this model\033[0m" ; echo "." 
		;;
	esac
	usdi=$(echo "scale=4; $pi / 10000" | bc -l )
	usdo=$(echo "scale=4; $po / 10000" | bc -l )
	tc=$(echo "scale=4; $pi * $numi / 1000 + $po * $numo / 1000" | bc -l )
	tcusd=$(echo "scale=9; $tc / 10000" | bc -l )
	TOTAL_COST_MICROCENT=$(echo "scale=4; $TOTAL_COST_MICROCENT + $tc" | bc -l )
	ttusd=$(echo "scale=9; $TOTAL_COST_MICROCENT / 10000" | bc -l )
	if $DEBUG_CALLS ; then (echo -n -e "\033[32m" ; echo "Debug output. Usage cost are " ; echo "$OPENAI_MODEL has microcent cost per 1K of $pi and $po" ; echo "There were $numi input and $numo output tokens" ; echo "Price for 1K token input is $(printf "%.4f" $usdi) and output is $(printf "%.4f" $usdo)" ; echo "Cost of this query was $(printf "%.4f" $tc) microcent or $(printf "%.7f" $tcusd) \$" ; echo "Total session cost so far $(printf "%.7f" $ttusd) \$" ; echo -n -e "\033[0m" ) >&2 ; fi

cat <<EOF > /dev/null	
Updated 2023-11-08 TODO: 
GPT-4 Turbo         	$0.0100   $0.0300	(gpt-4-1106-preview)
GPT-4V Turbo       		$0.0100   $0.0300	(gpt-4-vision-preview, gpt-4-1106-vision-preview = 85 tokens + 170 tokens per 512x512 tile)
GPT-4               	$0.0300   $0.0600	(gpt-4)
GPT-4 32K 	        	$0.0600   $0.1200	(gpt-4-32K)
GPT-3.5-Turbo	   		$0.0010   $0.0020	(gpt-3.5-turbo-1106, gpt-3.5-turbo, gpt-3.5-turbo-0301)
GPT-3.5-Turbo-Instruct	$0.0015   $0.0020	(gpt-3.5-turbo-instruct-0914, gpt-3.5-turbo-instruct)
GPT-3.5-Turbo 16K   	$0.0030   $0.0040	(gpt-3.5-turbo-16k-0613, gpt-3.5-turbo-16k)
Ada                 	$0.0004   $0.0004
Babbage             	$0.0005   $0.0005
Curie               	$0.0020   $0.0020
Davinci             	$0.0200   $0.0200
EOF
}

## calculate and store last image cost call
add_image_cost() {
	num="$NUMIMAGEGENS"
	p=0
	case "$SIZE" in
		256x256 )
		p=160
		;;
		512x512 )
		p=180
		;;
		1024x1024 )
		p=200
		;;
		*)
		;;
	esac
	usd=$(echo "scale=4; $p / 10000" | bc -l )
	tc=$(echo "scale=4; $p * $num" | bc -l )
	tcusd=$(echo "scale=9; $tc / 10000" | bc -l )
	TOTAL_COST_MICROCENT=$(echo "scale=4; $TOTAL_COST_MICROCENT + $tc" | bc -l )
	ttusd=$(echo "scale=9; $TOTAL_COST_MICROCENT / 10000" | bc -l )
	if $SHOW_INTERMEDIATE_COST ; then 
		echo -e "\033[33m>>> Cost of this query \033[1m$(printf "%.7f" $tcusd) \$\033[22m and total so far \033[1m$(printf "%.7f" $ttusd) \$\033[22m<<<\033[0m" ; 
		echo -e ">Query cost was $(printf "%.7f" $tcusd) \$ and total so far $(printf "%.7f" $ttusd) \$\n" >>~/.chatgpt_history ;
	fi
	if $DEBUG_CALLS ; then (echo -n -e "\033[32m" ; echo "Debug output. Usage cost are " ; echo "Image size $SIZE has microcent cost per image of $p" ; echo "There were $num images generated" ; echo "Cost of this query was $(printf "%.4f" $tc) microcent or $(printf "%.7f" $tcusd) \$" ; echo "Total session cost so far $(printf "%.7f" $ttusd) \$" ; echo -n -e "\033[0m" ) >&2 ; fi
		
cat <<EOF > /dev/null
For image generation it is
Resolution   Price
1024×1024    $0.0200 / image
512×512      $0.0180 / image
256×256      $0.0160 / image
EOF
}

# display intermediate cost of a call
display_intermediate_cost() {
	if $SHOW_INTERMEDIATE_COST ; then 
		echo -e "\033[33m>>> Cost of this query \033[1m$(printf "%.7f" $tcusd) \$\033[22m and total so far \033[1m$(printf "%.7f" $ttusd) \$\033[22m<<<\033[0m" ; 
		echo -e ">Query cost was $(printf "%.7f" $tcusd) \$ and total so far $(printf "%.7f" $ttusd) \$\n" >>~/.chatgpt_history ;
	fi
}

# request to openAI API models endpoint. Returns a list of models
# takes no input parameters
list_models() {
	models_response=$(curl https://api.openai.com/v1/models \
		-sS \
		-H "Authorization: Bearer $OPENAI_KEY")
	handle_error "$models_response"
	models_data=$(echo $models_response | jq -j -C '.data[] | {id, owned_by, created}')
	echo -e "$OVERWRITE_PROCESSING_LINE"
	echo -e "${CHATGPT_CYAN_LABEL}This is a list of models currently available at OpenAI API:\n ${models_data}"
}
# request to OpenAI API completions endpoint function
# $1 should be the request prompt
request_to_completions() {
	local prompt="$1"
	
	curl https://api.openai.com/v1/completions \
		-sS \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $OPENAI_KEY" \
		-d '{
  			"model": "'"$OPENAI_MODEL"'",
  			"prompt": "'"$prompt"'",
  			"max_tokens": '$OPENAI_MAX_TOKENS',
  			"temperature": '$OPENAI_TEMPERATURE'
			}'
}

# request to OpenAI API image generations endpoint function
# $1 should be the prompt
request_to_image() {
	local prompt="$1"

	if $DEBUG_CALLS ; then
		echo -n -e "\033[32m" >&2
		echo "Debug output. Request to https://api.openai.com/v1/images/generations is" >&2
		echo '{
    		"prompt": "'"${prompt#*image:}"'",
    		"n": '"${NUMIMAGEGENS}"',
    		"size": "'"$SIZE"'"
		}' >&2
		echo -n -e "\033[0m" >&2
	fi
	
	image_response=$(curl https://api.openai.com/v1/images/generations \
		-sS \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $OPENAI_KEY" \
		-d '{
    		"prompt": "'"${prompt#*image:}"'",
    		"n": '"${NUMIMAGEGENS}"',
    		"size": "'"$SIZE"'"
			}')
}

# request to OpenAPI API chat completion endpoint function
# $1 should be the message(s) formatted with role and content
request_to_chat() {
	local message="$1"
	escaped_system_prompt=$(escape "$SYSTEM_PROMPT")

	if $DEBUG_CALLS ; then
		echo -n -e "\033[32m" >&2
		echo "Debug output. Request to https://api.openai.com/v1/chat/completions is" >&2
		echo '{
            "model": "'"$OPENAI_MODEL"'",
            "messages": [
                {"role": "system", "content": "'"$escaped_system_prompt"'"},
                '"$message"'
                ],
            "max_tokens": '$OPENAI_MAX_TOKENS',
            "temperature": '$OPENAI_TEMPERATURE'
		}' >&2
		echo -n -e "\033[0m" >&2
	fi

	curl https://api.openai.com/v1/chat/completions \
		-sS \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $OPENAI_KEY" \
		-d '{
            "model": "'"$OPENAI_MODEL"'",
            "messages": [
                {"role": "system", "content": "'"$escaped_system_prompt"'"},
                '"$message"'
                ],
            "max_tokens": '$OPENAI_MAX_TOKENS',
            "temperature": '$OPENAI_TEMPERATURE'
            }'
}

# build chat context before each request for /completions (all models except
# gpt turbo and gpt 4)
# $1 should be the escaped request prompt,
# it extends $chat_context
build_chat_context() {
	local escaped_request_prompt="$1"
	if [ -z "$chat_context" ]; then
		chat_context="$CHAT_INIT_PROMPT\nQ: $escaped_request_prompt"
	else
		chat_context="$chat_context\nQ: $escaped_request_prompt"
	fi
}

escape() {
	echo "$1" | jq -Rrs 'tojson[1:-1]'
}

# maintain chat context function for /completions (all models except
# gpt turbo and gpt 4)
# builds chat context from response,
# keeps chat context length under max token limit
# * $1 should be the escaped response data
# * it extends $chat_context
maintain_chat_context() {
	local escaped_response_data="$1"
	# add response to chat context as answer
	chat_context="$chat_context${chat_context:+\n}\nA: $escaped_response_data"
	# check prompt length, 1 word =~ 1.3 tokens
	# reserving 100 tokens for next user prompt
	while (($(echo "$chat_context" | wc -c) * 1, 3 > (OPENAI_MAX_TOKENS - 100))); do
		# remove first/oldest QnA from prompt
		chat_context=$(echo "$chat_context" | sed -n '/Q:/,$p' | tail -n +2)
		# add init prompt so it is always on top
		chat_context="$CHAT_INIT_PROMPT $chat_context"
	done
}

# build user chat message function for /chat/completions (gpt models)
# builds chat message before request,
# $1 should be the escaped request prompt,
# it extends $chat_message
build_user_chat_message() {
	local escaped_request_prompt="$1"
	if [ -z "$chat_message" ]; then
		chat_message="{\"role\": \"user\", \"content\": \"$escaped_request_prompt\"}"
	else
		chat_message="$chat_message, {\"role\": \"user\", \"content\": \"$escaped_request_prompt\"}"
	fi
}

# adds the assistant response to the message in (chatml) format
# for /chat/completions (gpt models)
# keeps messages length under max token limit
# * $1 should be the escaped response data
# * it extends and potentially shrinks $chat_message
add_assistant_response_to_chat_message() {
	local escaped_response_data="$1"
	# add response to chat context as answer
	chat_message="$chat_message, {\"role\": \"assistant\", \"content\": \"$escaped_response_data\"}"

	# transform to json array to parse with jq
	local chat_message_json="[ $chat_message ]"
	# check prompt length, 1 word =~ 1.3 tokens
	# reserving 100 tokens for next user prompt
	while (($(echo "$chat_message" | wc -c) * 1, 3 > (OPENAI_MAX_TOKENS - 100))); do
		# remove first/oldest QnA from prompt
		chat_message=$(echo "$chat_message_json" | jq -c '.[2:] | .[] | {role, content}')
	done
}

# parse command line arguments
while [[ "$#" -gt 0 ]]; do
	case $1 in
	-i | --init-prompt)
		CHAT_INIT_PROMPT="$2"
		SYSTEM_PROMPT="$2"
		CONTEXT=true
		shift
		shift
		;;
	--init-prompt-from-file)
		CHAT_INIT_PROMPT=$(cat "$2")
		SYSTEM_PROMPT=$(cat "$2")
		CONTEXT=true
		shift
		shift
		;;
	-p | --prompt)
		prompt="$2"
		shift
		shift
		;;
	--prompt-from-file)
		prompt=$(cat "$2")
		shift
		shift
		;;
	-t | --temperature)
		OPENAI_TEMPERATURE="$2"
		shift
		shift
		;;
	--max-tokens)
		OPENAI_MAX_TOKENS="$2"
		shift
		shift
		;;
	-l | --list)
		list_models
		exit 0
		;;
	-m | --model)
		OPENAI_MODEL="$2"
		echo -e "Changed to model \033[31m${OPENAI_MODEL}\033[0m."
		shift
		shift
		;;
	-s | --size)
		SIZE="$2"
		shift
		shift
		;;
	-n | --numimages)
		NUMIMAGEGENS="$2"
		shift
		shift
		;;
	-b | --big-prompt)
		MULTI_LINE_PROMPT=true
		shift
		;;
	-c | --chat-context)
		CONTEXT=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	-r | --recall)
	    RECALL_A_CHAT=true
		shift
		;;
	-d | --debug)
		DEBUG_CALLS=true
		shift
		;;
	--md-only )
		MD_INTERPRETATION=false
		shift
		;;
	--nh )
		SAVE_HISTORY=false
		echo -e "Call parameter --nh. No history will be saved\n" >>~/.chatgpt_history
		shift
		;;
	--no-call-cost )
		SHOW_INTERMEDIATE_COST=false
		echo -e "Call parameter --nh. No history will be saved\n" >>~/.chatgpt_history
		shift
		;;
	--fold )
		FOLD=true
		FCOLUMNS="$2"
		shift
		shift
		;;
	*)
		echo "Unknown parameter: $1"
		exit 1
		;;
	esac
done

# set defaults
OPENAI_TEMPERATURE=${OPENAI_TEMPERATURE:-0.7}
OPENAI_MAX_TOKENS=${OPENAI_MAX_TOKENS:-1024}
OPENAI_MODEL=${OPENAI_MODEL:-gpt-3.5-turbo}
if [[ "$0" == *4 ]] ; then 
	OPENAI_MODEL="gpt-4";
fi
echo -e "Using default model \033[31m${OPENAI_MODEL}\033[0m."
SIZE=${SIZE:-256x256}
NUMIMAGEGENS=${NUMIMAGEGENS:-1}
CONTEXT=${CONTEXT:-false}
MULTI_LINE_PROMPT=${MULTI_LINE_PROMPT:-false}

# create our temp file for multi-line input
if [ $MULTI_LINE_PROMPT = true ]; then
	USER_INPUT_TEMP_FILE=$(mktemp)
	trap 'rm -f ${USER_INPUT}' EXIT
fi

# create history file
if [ ! -f ~/.chatgpt_history ]; then
	touch ~/.chatgpt_history
	chmod 600 ~/.chatgpt_history
fi

#mm detailed history to continue chat
CHATHIST_INDEX=~/.chatgpt_history_IDX
CHATHISTDIR=~/.chatgpt_history_files
chat_recall_number=""

save_hist_json_to_file() {
  local json_input="$1"
  
  # Create the directory if it doesn't exist
  if [ ! -d "$CHATHISTDIR" ]; then
	  echo mkdir -p -m 700 "$CHATHISTDIR"
  	mkdir -p -m 700 "$CHATHISTDIR"
  fi
  if [ ! -f "$CHATHIST_INDEX" ]; then
	  echo touch "$CHATHIST_INDEX"
	touch "$CHATHIST_INDEX"
	chmod 600 "$CHATHIST_INDEX"
  fi
  
  local smallest_number=1
  if [ ! -z "$chat_recall_number" ]; then
	  smallest_number="$chat_recall_number"
  else
	  checkempty=$(ls "$CHATHISTDIR" | grep -o '^[0-9]*')
	  if [ -z "$checkempty" ]; then
		  smallest_number=1
	  else
		  smallest_number=$(ls "$CHATHISTDIR" | grep -o '^[0-9]*' | sort -n | tail -1 | awk '{ if ($1 ~ /^[0-9]+$/) { print $1 + 1 } else { print 1 } }')
	  fi
  fi

  local file_name="${CHATHISTDIR}/${smallest_number}.json"
  echo "$json_input" > "$file_name"
  if [ -z "$chat_recall_number" ]; then
	  length=$(echo "[${json_input}]" | jq '. | length');
	  local first_content=$(echo "[${json_input}]" | jq -r '.[0].content')
	  local truncated_content="${first_content:0:50}"
	  local line="${smallest_number}) ${truncated_content} (${length} items)"
	  echo "$line" >> "$CHATHIST_INDEX"
  fi
  echo "Saved chat to $file_name"
#  echo "$line"
#  echo "$json_input"
}

review_full() {
	 length=$(echo "[${chat_message}]" | jq '. | length');
	 for ((i = 0; i < length; i++)); do
		 zrole=$(echo -n "[${chat_message}]" | jq -j ".[$i].role")
		 echo -e "\033[31m${zrole}\033[0m"
		 if $MD_INTERPRETATION && command -v mdcat &>/dev/null; then
			 echo "[${chat_message}]" | jq -r ".[$i].content" | mdcat -
		 elif $MD_INTERPRETATION && command -v glow &>/dev/null; then
			 echo "[${chat_message}]" | jq -r ".[$i].content" | glow -
		 else
			 echo "[${chat_message}]" | jq -r ".[$i].content"
		 fi
	 done
}

review_short() {
	 length=$(echo "[${chat_message}]" | jq '. | length');
	 for ((i = 0; i < length; i++)); do
		 zrole=$(echo -n "[${chat_message}]" | jq -j ".[$i].role")
		 zmessage=$(echo "[${chat_message}]" | jq -r ".[$i].content")
		 echo -e "\033[31m${zrole}\033[0m: ${zmessage:0:50}"
	 done
}

redisplay_chat() {
	echo -e "Using default model \033[31m${OPENAI_MODEL}\033[0m."
	echo -e "Welcome to chatgpt. You can quit with '\033[36mexit\033[0m' or '\033[36mq\033[0m'."
	length=$(echo "[${chat_message}]" | jq '. | length');
	for ((i = 0; i < length; i++)); do
		zrole=$(echo -n "[${chat_message}]" | jq -j ".[$i].role")
		if [[ "$zrole" == "user" ]]; then
			echo -e "\nEnter a prompt:"
			# use -j instead of -r to avoid extra newline added by the "escape" funtion
			echo -n "[${chat_message}]" | jq -j ".[$i].content"
			echo -ne $PROCESSING_LABEL
		else
			zresponse=$(echo "[${chat_message}]" | jq -r ".[$i].content")
			echo -e "$OVERWRITE_PROCESSING_LINE"
			# if glow installed, print parsed markdown
			if $MD_INTERPRETATION && command -v mdcat &>/dev/null; then
				echo -e "${CHATGPT_CYAN_LABEL}"
				echo -ne "${zresponse}" | mdcat -
			elif $MD_INTERPRETATION && command -v glow &>/dev/null; then
				echo -e "${CHATGPT_CYAN_LABEL}"
				echo -n "${zresponse}" | glow -
			else
				if $FOLD ; then
					echo -ne "${CHATGPT_CYAN_LABEL}${zresponse}"  | fold -s -w "$FCOLUMNS"
				else
					echo -ne "${CHATGPT_CYAN_LABEL}${zresponse}" 
				fi
			fi
		fi
	done
}


recall_chat() {
	NUM="$1"
	#recall
	echo "recall: $NUM"
	 file_name="${CHATHISTDIR}/${NUM}.json"
	 if [ -e "$file_name" ]; then
		 if [[ ! -z "${chat_message}" ]]; then
			 save_hist_json_to_file "${chat_message}"
		 fi
		 chat_message=$(cat "$file_name")
		 chat_recall_number=$NUM
		 review_short
		 echo 
	 else
		echo "There is no history file for ${NUM} (${file_name})" 
	fi	
}

truncate_chat() {
	echo "Here is the previous chat truncated to 50 characters:"
	 length=$(echo "[${chat_message}]" | jq '. | length');
	 for ((i = 0; i < length; i++)); do
		 zrole=$(echo -n "[${chat_message}]" | jq -j ".[$i].role")
		 zmessage=$(echo -n "[${chat_message}]" | jq -r ".[$i].content")
		 echo -e "${i}.	\033[31m${zrole}\033[0m: ${zmessage:0:50}"
	 done
	echo -e "\nEnter the number of the first item to cut off:"
	read -e trn
	if (( "$trn" >=0 && "$trn" < length)) ; then
		truncated_chat=$(echo -n "[${chat_message}]" | jq ".[:$trn]")
		chat_recall_number=""
		chat_message="${truncated_chat:1:-1}"
	else
		echo "${trn} out of range"
	fi
}

if $RECALL_A_CHAT ; then
	#recall if asked for
	cat "$CHATHIST_INDEX"
	echo -e "\nEnter the number of the chat to recall:"
	read -e chattorecall
	recall_chat "$chattorecall"
fi

running=true
# check input source and determine run mode

# prompt from argument, run on pipe mode (run once, no chat)
if [ -n "$prompt" ]; then
	pipe_mode_prompt=${prompt}
# if input file_descriptor is a terminal, run on chat mode
elif [ -t 0 ]; then
	echo -e "Welcome to chatgpt. You can quit with '\033[36mexit\033[0m' or '\033[36mq\033[0m'."
# prompt from pipe or redirected stdin, run on pipe mode
else
	pipe_mode_prompt+=$(cat -)
fi

while $running; do

	if [ -z "$pipe_mode_prompt" ]; then
		if [ $MULTI_LINE_PROMPT = true ]; then
			echo -e "\nEnter a prompt: (Press Enter then Ctrl-D to send)"
			cat >"${USER_INPUT_TEMP_FILE}"
			input_from_temp_file=$(cat "${USER_INPUT_TEMP_FILE}" )
			prompt=$(escape "$input_from_temp_file")
		else
			echo -e "\nEnter a prompt:"
			read -e prompt
		fi
		if [[ ! $prompt =~ ^(exit|q)$ ]]; then
			echo -ne $PROCESSING_LABEL
		fi
	else
		# set vars for pipe mode
		prompt=${pipe_mode_prompt}
		running=false
		CHATGPT_CYAN_LABEL=""
	fi

	#fix multiline which is escape
	if [[ $prompt =~ ^(exit|q)(\\n)?$ ]]; then
		#save current chat context	
		# echo "chat_message is "
		if [[ ! -z "${chat_message}" ]]; then
			if $SAVE_HISTORY ; then save_hist_json_to_file "${chat_message}" ; fi
		fi
		running=false
		
		#print session cost
		ttusd=$(echo "scale=9; $TOTAL_COST_MICROCENT / 10000" | bc -l )
		echo -e "\033[31m>>>Total session cost was \033[1m$(printf "%.7f" $ttusd) \$\033[22m<<<\033[0m"
		echo -e "> Total session cost was $(printf "%.7f" $ttusd) \$\n" >>~/.chatgpt_history
		
	#add help as a command
	elif [[ $prompt =~ ^(help|h)(\\n)?$ ]] ; then
		commandhelp

	#toggle md output
	elif [[ $prompt =~ ^(md)(\\n)?$ ]] ; then
		if $MD_INTERPRETATION ; then 
			MD_INTERPRETATION=false
			echo
		else
			MD_INTERPRETATION=true
		fi
		if $MD_INTERPRETATION && command -v mdcat &>/dev/null; then
			echo "Will use mdcat for display"
		elif $MD_INTERPRETATION && command -v glow &>/dev/null; then
			echo "Will use glow for display"
		else
			echo "Will output plain markdown"
		fi
	elif [[ $prompt =~ ^(newchat|nc)(\\n)?$ ]] ; then
		#save history
		if [[ ! -z "${chat_message}" ]]; then
			save_hist_json_to_file "${chat_message}"
		fi		
		#clear
		chat_message=""
		chat_context=""
		chat_recall_number=""
		echo "Starting new chat."

	#add option to change model
	elif [[ "$prompt" =~ ^cm(\\n)?$ ]]; then
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			echo "Type for ..."
			echo "1 = gpt-4"
			echo "2 = gpt-3.5-turbo"
			echo "3 = gpt-3.5-turbo-16k"
			echo -e "\nEnter the number of model to switch to or directly a model name:"
			read -e switch_to_num
			case "$switch_to_num" in
				1)
				MNEW="gpt-4"
				;;
				2)
				MNEW="gpt-3.5-turbo"
				;;
				3)
				MNEW="gpt-3.5-turbo-16k"
				;;				*)
				MNEW="$switch_to_num"
				;;
			esac
			echo -e "Changing from model \033[31m${OPENAI_MODEL}\033[0m to model \033[31m${MNEW}\033[0m."
			OPENAI_MODEL=$MNEW
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^cm4(\\n)?$ ]]; then
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			MNEW="gpt-4"
			echo -e "Changing from model \033[31m${OPENAI_MODEL}\033[0m to model \033[31m${MNEW}\033[0m."
			OPENAI_MODEL=$MNEW
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^cm3(\\n)?$ ]]; then
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			MNEW="gpt-3.5-turbo"
			echo -e "Changing from model \033[31m${OPENAI_MODEL}\033[0m to model \033[31m${MNEW}\033[0m."
			OPENAI_MODEL=$MNEW
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^cm:([a-zA-Z0-9.-]+)(\\n)?$ ]]; then
		MNEW="${BASH_REMATCH[1]}"
		if [[ "$MNEW" =~ ^gpt- ]] && [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			echo -e "Changing from model \033[31m${OPENAI_MODEL}\033[0m to model \033[31m${MNEW}\033[0m."
			OPENAI_MODEL=$MNEW
		else
			echo "only available for chat models gpt-*"
		fi

	elif [[ "$prompt" =~ ^(review|rv)(\\n)?$ ]]; then
		#show current chat so far
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			echo "Here is the previous chat in full:"
			review_full
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^(redisplaychat|rd)(\\n)?$ ]]; then
		#redisplay chat in chatstyle
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			echo "Re-displaying the chat."
			echo -ne "Would you like to \033[31mreset\033[0m the screen? "
			read -p "(y, yes or <return> to reset) " choice
			if [ "$choice" == "y" ] || [ "$choice" == "yes" ] || [ ${#choice} -eq 0 ] ; then
				reset
			fi
			redisplay_chat
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^(reviewshort|rs)(\\n)?$ ]]; then
		#show current chat so far abbreviated
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			echo "Here is the previous chat truncated to 50 characters:"
			review_short
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^(truncate|tr)(\\n)?$ ]]; then
		#truncate current chat 
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			truncate_chat
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^(recall|rc)(\\n)?$ ]]; then
		#recall a previous chat
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			tail -10 "$CHATHIST_INDEX"
			echo -e "\nEnter the number of the chat to recall:"
			read -e chattorecall
			recall_chat "$chattorecall"
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^(recallfull|rcf)(\\n)?$ ]]; then
		#recall history
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			less "$CHATHIST_INDEX"
			echo -e "\nEnter the number of the chat to recall:"
			read -e chattorecall
			recall_chat "$chattorecall"
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^rc:([0-9]+) ]]; then
		NUM="${BASH_REMATCH[1]}"
		if [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
			recall_chat "$NUM"
		else
			echo "only available for chat models gpt-*"
		fi
	elif [[ "$prompt" =~ ^image: ]]; then
		request_to_image "$prompt"
		handle_error "$image_response"
		if $DEBUG_CALLS ; then ( echo -n -e "\033[32m" ; echo "Debug output. Response is " ; echo $image_response ; echo -n -e "\033[0m" ) >&2 ; fi 
		add_image_cost
		nameelement=$(echo "$image_response" | jq -r '.created')
		echo -e "$OVERWRITE_PROCESSING_LINE"
		declare -a savetofilenames
		for ((i = 0; i < NUMIMAGEGENS; i++)); do
			iform=$(printf "%02d" $i)
			savetofilenames[$i]="DUMMY_${iform}"
		done
		declare -a image_url
		#NUMIMAGEGENS
		# three arguments ...  a name element ... number of files ... a string array for the filenames
		while ! prompt_filename "$nameelement" "$NUMIMAGEGENS" savetofilenames ; do
  			echo "Please enter a different filename or confirm overwriting."
		done
		echo -e "${CHATGPT_CYAN_LABEL}Your image was created. \n"
		for ((i = 0; i < num; i++)); do
			#test:
			#image_url[$i]="https://upload.wikimedia.org/wikipedia/commons/thumb/6/6a/PNG_Test.png/191px-PNG_Test.png"
			image_url[$i]=$(echo "$image_response" | jq -r '.data['${i}'].url')
			echo -e "\nLink: ${image_url[i]}\n"
			curl -sS "${image_url[i]}" -o "${savetofilenames[i]}"
		done
		if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
			for ((i = 0; i < num; i++)); do
				echo -e "\n${savetofilenames[i]}\n"
				imgcat "${savetofilenames[i]}"
			done
		elif [[ "$TERM" == "xterm-kitty" ]]; then
			for ((i = 0; i < num; i++)); do
				echo -e "\n${savetofilenames[i]}\n"
				kitty +kitten icat "${savetofilenames[i]}"
			done
		fi
		timestamp=$(date +"%Y-%m-%d %H:%M")
		if $SAVE_HISTORY ; then echo -e "$timestamp $prompt \n" >>~/.chatgpt_history ; fi
		for ((i = 0; i < num; i++)); do
		 	if $SAVE_HISTORY ; then echo -e "\t${image_url[i]}\n" >>~/.chatgpt_history ; fi 
		done
	elif [[ "$prompt" == "history" ]]; then
		echo -e "\n$(cat ~/.chatgpt_history)"
	elif [[ "$prompt" == "models" ]]; then
		list_models
	elif [[ "$prompt" =~ ^model: ]]; then
		models_response=$(curl https://api.openai.com/v1/models \
			-sS \
			-H "Authorization: Bearer $OPENAI_KEY")
		handle_error "$models_response"
		model_data=$(echo $models_response | jq -r -C '.data[] | select(.id=="'"${prompt#*model:}"'")')
		echo -e "$OVERWRITE_PROCESSING_LINE"
		echo -e "${CHATGPT_CYAN_LABEL}Complete details for model: ${prompt#*model:}\n ${model_data}"
#for later
#	elif [( "$prompt" =~ ^wolfram: ]]; then		
	elif [[ "$prompt" =~ ^command: ]]; then
		# escape quotation marks, new lines, backslashes...
		escaped_prompt=$(escape "$prompt")
		escaped_prompt=${escaped_prompt#command:}
		request_prompt=$COMMAND_GENERATION_PROMPT$escaped_prompt
		build_user_chat_message "$request_prompt"
		response=$(request_to_chat "$chat_message")
		if $DEBUG_CALLS ; then ( echo -n -e "\033[32m" ; echo "Debug output. Response is " ; echo $response ; echo -n -e "\033[0m" ) >&2 ; fi 
		handle_error "$response"
		#add_cost
		add_cost $(echo $response | jq -r '.usage.prompt_tokens') $(echo $response | jq -r '.usage.completion_tokens')
		response_data=$(echo $response | jq -r '.choices[].message.content')

		if [[ "$prompt" =~ ^command: ]]; then
			echo -e "$OVERWRITE_PROCESSING_LINE"
			if $FOLD ; then
				echo -e "${CHATGPT_CYAN_LABEL} ${response_data}" | fold -s -w "$FCOLUMNS"
			else
				echo -e "${CHATGPT_CYAN_LABEL} ${response_data}" 
			fi
			dangerous_commands=("rm" ">" "mv" "mkfs" ":(){:|:&};" "dd" "chmod" "wget" "curl")

			for dangerous_command in "${dangerous_commands[@]}"; do
				if [[ "$response_data" == *"$dangerous_command"* ]]; then
					echo "Warning! This command can change your file system or download external scripts & data. Please do not execute code that you don't understand completely."
				fi
			done
			echo "Would you like to execute it? (Yes/No)"
			read run_answer
			if [ "$run_answer" == "Yes" ] || [ "$run_answer" == "yes" ] || [ "$run_answer" == "y" ] || [ "$run_answer" == "Y" ]; then
				echo -e "\nExecuting command: $response_data\n"
				eval $response_data
			fi
		fi
		add_assistant_response_to_chat_message "$(escape "$response_data")"

		display_intermediate_cost

		timestamp=$(date +"%Y-%m-%d %H:%M")
		if $SAVE_HISTORY ; then echo -e "$timestamp $prompt \n$response_data \n" >>~/.chatgpt_history ; fi
	elif [[ "$OPENAI_MODEL" =~ ^gpt- ]]; then
		if [ ${#prompt} -lt 3 ] ; then
		echo -ne "\033[31mWARNING: Very short prompt!\033[0m "
			read -p "Send to ChatGPT or renter? (y, yes or <return> to send) " choice
			if [ "$choice" != "y" ] && [ "$choice" != "yes" ] && [ ${#choice} -gt 0 ] ; then
				continue;
			fi
		fi

		# escape quotation marks, new lines, backslashes...
		request_prompt=$(escape "$prompt")

		build_user_chat_message "$request_prompt"

		response=$(request_to_chat "$chat_message")
		if $DEBUG_CALLS ; then ( echo -n -e "\033[32m" ; echo "Debug output. Response is " ; echo $response ; echo -n -e "\033[0m" ) >&2 ; fi
		handle_error "$response"
		#add_cost
		add_cost $(echo $response | jq -r '.usage.prompt_tokens') $(echo $response | jq -r '.usage.completion_tokens')
		response_data=$(echo "$response" | jq -r '.choices[].message.content')

		echo -e "$OVERWRITE_PROCESSING_LINE"
		# if glow installed, print parsed markdown
		if $MD_INTERPRETATION && command -v mdcat &>/dev/null; then
			echo -e "${CHATGPT_CYAN_LABEL}"
			echo "${response_data}" | mdcat -
		elif $MD_INTERPRETATION && command -v glow &>/dev/null; then
			echo -e "${CHATGPT_CYAN_LABEL}"
			echo "${response_data}" | glow -
		else
			if $FOLD ; then
				echo -e "${CHATGPT_CYAN_LABEL}${response_data}" | fold -s -w "$FCOLUMNS"
			else
				echo -e "${CHATGPT_CYAN_LABEL}${response_data}"
			fi
		fi
		add_assistant_response_to_chat_message "$(escape "$response_data")"

		display_intermediate_cost

		timestamp=$(date +"%Y-%m-%d %H:%M")
		if $SAVE_HISTORY ; then echo -e "$timestamp $prompt \n$response_data \n" >>~/.chatgpt_history ; fi
	else
		# escape quotation marks, new lines, backslashes...
		request_prompt=$(escape "$prompt")

		if [ "$CONTEXT" = true ]; then
			build_chat_context "$request_prompt"
		fi

		response=$(request_to_completions "$request_prompt")
		handle_error "$response"
		#add_cost
		add_cost $(echo $response | jq -r '.usage.prompt_tokens') $(echo $response | jq -r '.usage.completion_tokens')
		response_data=$(echo "$response" | jq -r '.choices[].text')

		echo -e "$OVERWRITE_PROCESSING_LINE"
		# if mdcat or glow installed, print parsed markdown
		if $MD_INTERPRETATION && command -v mdcat &>/dev/null; then
			echo -e "${CHATGPT_CYAN_LABEL}"
			echo "${response_data}" | mdcat -
		elif $MD_INTERPRETATION && command -v glow &>/dev/null; then
			echo -e "${CHATGPT_CYAN_LABEL}"
			echo "${response_data}" | glow -
		else
			# else remove empty lines and print
			formatted_text=$(echo "${response_data}" | sed '1,2d; s/^A://g')
			if $FOLD ; then
				echo -e "${CHATGPT_CYAN_LABEL}${formatted_text}"  | fold -s -w "$FCOLUMNS"
			else
				echo -e "${CHATGPT_CYAN_LABEL}${formatted_text}"
			fi
		fi

		if [ "$CONTEXT" = true ]; then
			maintain_chat_context "$(escape "$response_data")"
		fi

		display_intermediate_cost

		timestamp=$(date +"%Y-%m-%d %H:%M")
		if $SAVE_HISTORY ; then echo -e "$timestamp $prompt \n$response_data \n" >>~/.chatgpt_history ; fi
	fi
done

# if running on pipe mode, exit here
if [ ! -z "$pipe_mode_prompt" ]; then
	if [[ ! -z "${chat_message}" ]]; then
		save_hist_json_to_file "${chat_message}"
	fi
	#print session cost
	ttusd=$(echo "scale=9; $TOTAL_COST_MICROCENT / 10000" | bc -l )
	echo -e "\033[31m>>>Total session cost was \033[1m$(printf "%.7f" $ttusd) \$\033[22m<<<\033[0m"
	echo -e "> Total session cost was $(printf "%.7f" $ttusd) \$\n" >>~/.chatgpt_history
fi
