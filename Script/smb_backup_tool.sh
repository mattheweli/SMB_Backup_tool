#!/bin/sh

# ==============================================================================
# SMB BACKUP TOOL v1.0.2 (CRON FIX)
# Description: Backup local folders to remote SMB share
# Changelog:
#   - v1.0.2: Fixed cron job creation and retrofix    
#   - v1.0.1: Fixed 'tar' compatibility for BusyBox (switched --exclude-from to -X)
# ==============================================================================

export PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin

# --- CONFIGURATION ---
VERSION="1.0.2"
CONFIG_FILE="/opt/etc/smb_backup.cfg"
LOG_FILE="/opt/var/log/smb_backup.log"
TEMP_DIR="/opt/tmp/backup_workdir"
CRON_FILE="/opt/etc/crontab"  # File target per Entware

# Filtro Log per avvisi innocui
LOG_FILTER="NT_STATUS_OBJECT_NAME_COLLISION|Can't load|dos charset"

# Colors
CGreen="\e[1;32m"
CRed="\e[1;31m"
CYellow="\e[1;33m"
CBlue="\e[1;34m"
CWhite="\e[1;37m"
CClear="\e[0m"
InvDkGray="\e[1;100m"

# --- UTILITY FUNCTIONS ---

check_and_fix_cron_user() {
    SCRIPT_PATH=$(readlink -f "$0")
    # Verifica se il file crontab esiste
    if [ -f "$CRON_FILE" ]; then
        # Cerca se lo script è presente nel crontab MA NON preceduto da "root"
        if grep -Fq "$SCRIPT_PATH" "$CRON_FILE" && ! grep -Fq "root $SCRIPT_PATH" "$CRON_FILE"; then
            logger_msg "Detected malformed CRON entry (missing user). Fixing..." "WARN"
            
            # Usa sed per inserire "root " prima del percorso dello script
            # Cerca: (qualcosa che finisce con spazio) (/percorso/dello/script)
            # Sostituisci con: \1root \2
            sed -i "s|\(.*\) \($SCRIPT_PATH\)|\1 root \2|" "$CRON_FILE"
            
            # Verifica se la correzione è andata a buon fine
            if grep -Fq "root $SCRIPT_PATH" "$CRON_FILE"; then
                logger_msg "CRON entry fixed successfully." "INFO"
                restart_cron_service
            else
                logger_msg "Failed to fix CRON entry automatically." "ERROR"
            fi
        fi
    fi
}

logger_msg() {
    TYPE=$2; [ -z "$TYPE" ] && TYPE="INFO"
    echo -e "$(date "+%Y-%m-%d %H:%M:%S") [${TYPE}] $1" >> "$LOG_FILE"
    case $TYPE in
        "ERROR") echo -e "${CRed}[ERROR] $1${CClear}" ;;
        "WARN")  echo -e "${CYellow}[WARN]  $1${CClear}" ;;
        *)       echo -e "${CGreen}[INFO]  $1${CClear}" ;;
    esac
}

load_config() {
    CONFIG_STATUS="MISSING"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        [ ! -z "$SMB_PASS_ENC" ] && SMB_PASS=$(echo "$SMB_PASS_ENC" | base64 -d 2>/dev/null)
        [ -z "$AUTO_PURGE" ] && AUTO_PURGE="true"
        [ -z "$CRON_LABEL" ] && CRON_LABEL="Not Configured"

        if [ ! -z "$SMB_HOST" ] && [ ! -z "$SMB_SHARE" ]; then
            CONFIG_STATUS="OK"
        else
            CONFIG_STATUS="INVALID"
        fi
    fi
}

save_config() {
    PASS_ENC=$(echo -n "$SMB_PASS" | base64)
    cat <<EOF > "$CONFIG_FILE"
# SMB Backup Tool Configuration (v$VERSION)
SMB_HOST="$SMB_HOST"
SMB_SHARE="$SMB_SHARE"
SMB_SUBDIR="$SMB_SUBDIR"
SMB_USER="$SMB_USER"
SMB_PASS_ENC="$PASS_ENC"
SOURCE_DIR="$SOURCE_DIR"
RETENTION_DAYS="$RETENTION_DAYS"
AUTO_PURGE="$AUTO_PURGE"
CRON_LABEL="$CRON_LABEL"
EOF
    chmod 600 "$CONFIG_FILE"
    logger_msg "Configuration saved to $CONFIG_FILE" "INFO"
    load_config
}

check_dependencies() {
    if ! which smbclient >/dev/null 2>&1; then
        echo -e "${CRed}ERROR: smbclient not found. Run: opkg install samba4-client${CClear}"
        exit 1
    fi
    if [ ! -e /usr/bin/ndmc ] && [ ! -e /bin/ndmc ]; then
         echo -e "${CYellow}WARN: ndmc (CLI) not found. Config backup might fail.${CClear}"
    fi
}

# --- ENTWARE CRON FUNCTIONS (v1.0.2) ---

restart_cron_service() {
    # Riavvia il servizio cron per applicare le modifiche
    if [ -x /opt/etc/init.d/S10cron ]; then
        /opt/etc/init.d/S10cron restart >/dev/null 2>&1
    elif which crond >/dev/null 2>&1; then
        killall crond 2>/dev/null
        crond
    fi
}

get_cron_status() {
    SCRIPT_PATH=$(readlink -f "$0")
    CRON_CMD="$SCRIPT_PATH -run"
	
	FULL_LINE="$CRON_STR root $CRON_CMD"
    
    if [ -f "$CRON_FILE" ] && grep -Fq "$CRON_CMD" "$CRON_FILE"; then
        echo "ACTIVE"
    else
        echo "INACTIVE"
    fi
}

configure_schedule_wizard() {
    clear
    echo -e "${CBlue}--- AUTOMATIC SCHEDULE WIZARD ---${CClear}"
    echo "This will edit: $CRON_FILE"
    echo ""
    echo "Select Frequency:"
    echo " 1. Daily (Every day)"
    echo " 2. Weekly (Every Sunday)"
    echo " 3. Bi-Weekly (Every 15 days - 1st, 16th, 31st)"
    echo " 4. Monthly (1st of month)"
    echo ""
    read -p "Choice [1-4]: " FREQ_OPT

    echo ""
    read -p "Enter Hour (0-23) [e.g. 03]: " IN_HOUR
    read -p "Enter Minute (0-59) [e.g. 00]: " IN_MIN

    if [ -z "$IN_HOUR" ]; then IN_HOUR="03"; fi
    if [ -z "$IN_MIN" ]; then IN_MIN="00"; fi
    
    case "$FREQ_OPT" in
        1) # Daily
           CRON_STR="$IN_MIN $IN_HOUR * * *"
           LABEL_STR="Daily at $IN_HOUR:$IN_MIN"
           ;;
        2) # Weekly
           CRON_STR="$IN_MIN $IN_HOUR * * 0"
           LABEL_STR="Weekly (Sun) at $IN_HOUR:$IN_MIN"
           ;;
        3) # Bi-Weekly
           CRON_STR="$IN_MIN $IN_HOUR */15 * *"
           LABEL_STR="Every 15 days at $IN_HOUR:$IN_MIN"
           ;;
        4) # Monthly
           CRON_STR="$IN_MIN $IN_HOUR 1 * *"
           LABEL_STR="Monthly (1st) at $IN_HOUR:$IN_MIN"
           ;;
        *) 
           echo "Invalid option."
           return
           ;;
    esac

    SCRIPT_PATH=$(readlink -f "$0")
    CRON_CMD="$SCRIPT_PATH -run"
    FULL_LINE="$CRON_STR $CRON_CMD"
    
    # --- WRITE TO FILE (v1.2.8) ---
    if [ ! -f "$CRON_FILE" ]; then touch "$CRON_FILE"; fi
    
    # 1. Rimuove eventuali vecchie righe che contengono il comando (usando # come delimitatore)
    sed -i "\#$CRON_CMD#d" "$CRON_FILE"
    
    # 2. Accoda la nuova riga
    echo "$FULL_LINE" >> "$CRON_FILE"
    
    # 3. Aggiorna etichetta e riavvia servizio
    CRON_LABEL="$LABEL_STR"
    save_config
    restart_cron_service
    
    echo -e "${CGreen}Schedule updated in $CRON_FILE: $LABEL_STR${CClear}"
    logger_msg "Scheduler updated ($CRON_FILE) to: $LABEL_STR" "INFO"
    read -p "Press Enter..."
}

disable_scheduler() {
    SCRIPT_PATH=$(readlink -f "$0")
    CRON_CMD="$SCRIPT_PATH -run"
    
    if [ -f "$CRON_FILE" ]; then
        # Rimuove la riga dal file fisico
        sed -i "\#$CRON_CMD#d" "$CRON_FILE"
        restart_cron_service
    fi
    
    CRON_LABEL="Disabled"
    save_config
    
    echo -e "${CYellow}Scheduler disabled (entry removed from $CRON_FILE).${CClear}"
    logger_msg "Scheduler disabled by user." "INFO"
    read -p "Press Enter..."
}

scheduler_menu() {
    while true; do
        clear
        STATUS=$(get_cron_status)
        if [ "$STATUS" == "ACTIVE" ]; then STATUS_COL="${CGreen}ACTIVE${CClear}"; else STATUS_COL="${CRed}INACTIVE${CClear}"; fi
        
        echo -e "${CBlue}--- SCHEDULER MENU (Entware) ---${CClear}"
        echo -e "File   : $CRON_FILE"
        echo -e "Status : $STATUS_COL"
        echo -e "Current: $CRON_LABEL"
        echo ""
        echo " 1. Configure New Schedule (Wizard)"
        echo " 2. Disable Scheduler"
        echo " 3. Return to Main Menu"
        echo ""
        read -p "Select: " SCH_OPT
        case "$SCH_OPT" in
            1) configure_schedule_wizard ;;
            2) disable_scheduler ;;
            3) return ;;
        esac
    done
}

# --- SYSTEM DUMP FUNCTIONS ---

dump_system_files() {
    logger_msg "Exporting System Configuration..." "INFO"
    mkdir -p "$TEMP_DIR/sys_dump"
    
    # RUNNING CONFIG (via NDMC)
    logger_msg "Executing 'show running-config' via CLI..." "INFO"
    CONFIG_FILE_TXT="$TEMP_DIR/sys_dump/running-config.txt"
    
    if ndmc -c "show running-config" > "$CONFIG_FILE_TXT" 2>/dev/null; then
         if [ -s "$CONFIG_FILE_TXT" ]; then
             ESC=$(printf '\033')
             sed -i "s/${ESC}\[[0-9;]*[a-zA-Z]//g" "$CONFIG_FILE_TXT"
             sed -i "s/${ESC}\[K//g" "$CONFIG_FILE_TXT"
             tr -d '\r' < "$CONFIG_FILE_TXT" > "$CONFIG_FILE_TXT.tmp" && mv "$CONFIG_FILE_TXT.tmp" "$CONFIG_FILE_TXT"
             logger_msg "Config exported and cleaned successfully." "INFO"
         else
             logger_msg "Config export created an empty file." "WARN"
         fi
    else
         echo "show running-config" | ndmc > "$CONFIG_FILE_TXT" 2>/dev/null
         [ -s "$CONFIG_FILE_TXT" ] && sed -i "s/$(printf '\033')\[[0-9;]*[a-zA-Z]//g" "$CONFIG_FILE_TXT"
         logger_msg "Config exported via pipe fallback." "INFO"
    fi
}

# --- BACKUP LOGIC ---

test_connection() {
    logger_msg "Testing connection to //${SMB_HOST}/${SMB_SHARE}..." "INFO"
    TEST_OUT=$(smbclient "//${SMB_HOST}/${SMB_SHARE}" -U "${SMB_USER}%${SMB_PASS}" -c "ls" 2>&1 | grep -vE "$LOG_FILTER")
    
    if [ $? -eq 0 ]; then
        logger_msg "SMB Connection Successful." "INFO"
        return 0
    else
        logger_msg "SMB Connection Failed. Output: $TEST_OUT" "ERROR"
        return 1
    fi
}

perform_cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

perform_backup() {
    if [ "$CONFIG_STATUS" != "OK" ]; then logger_msg "Configuration invalid or missing." "ERROR"; return; fi
    
    echo -e "${CGreen}Backup started. Policy: keep last ${RETENTION_DAYS} days.${CClear}"
    logger_msg "Backup Started. Policy: $RETENTION_DAYS days, AutoPurge: $AUTO_PURGE." "INFO"

    # Init Clean
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    DATE_STR=$(date "+%Y%m%d_%H%M%S")
    REMOTE_FOLDER_NAME="${DATE_STR}"
    
    # --- STEP 1: PREPARE ARCHIVES ---
    dump_system_files
    
    ARCHIVE_SYS="sys_backup_${DATE_STR}.tar.gz"
    tar -czf "$TEMP_DIR/$ARCHIVE_SYS" -C "$TEMP_DIR/sys_dump" . 2>/dev/null
    
    ARCHIVE_OPT="opt_backup_${DATE_STR}.tar.gz"
    logger_msg "Archiving $SOURCE_DIR (Compression started)..." "INFO"
    
    START_TIME=$(date +%s)
    
    # --- EXCLUSION LIST ---
    echo "opt/var/log" > "$TEMP_DIR/exclude.txt"
    echo "opt/tmp" >> "$TEMP_DIR/exclude.txt"
    echo "opt/backup_storage" >> "$TEMP_DIR/exclude.txt"
    
    # FIX for BusyBox tar: use -X instead of --exclude-from
    tar -X "$TEMP_DIR/exclude.txt" -czf "$TEMP_DIR/$ARCHIVE_OPT" -C "$(dirname $SOURCE_DIR)" "$(basename $SOURCE_DIR)" 2>/tmp/tar_err
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    if [ $DURATION -gt 59 ]; then
        MINUTES=$((DURATION / 60)); SECONDS=$((DURATION % 60)); TIME_STR="${MINUTES}m ${SECONDS}s"
    else
        TIME_STR="${DURATION}s"
    fi
    logger_msg "Compression completed in: $TIME_STR" "INFO"
    
    # --- STEP 2: UPLOAD ---
    
    if [ -f "$TEMP_DIR/$ARCHIVE_OPT" ]; then
        SIZE_OPT=$(du -h "$TEMP_DIR/$ARCHIVE_OPT" | cut -f1)
        logger_msg "Archives ready. OPT size: $SIZE_OPT. Uploading..." "INFO"
        
        PATH_CMDS=""
        CLEAN_PATH=$(echo "$SMB_SUBDIR" | sed 's/\// /g')
        for folder in $CLEAN_PATH; do
             if [ ! -z "$folder" ] && [ "$folder" != "." ]; then
                 PATH_CMDS="$PATH_CMDS mkdir \"$folder\"; cd \"$folder\";"
             fi
        done
        
        FULL_CMDS="$PATH_CMDS mkdir \"$REMOTE_FOLDER_NAME\"; cd \"$REMOTE_FOLDER_NAME\"; lcd \"$TEMP_DIR\"; put \"$ARCHIVE_SYS\"; put \"$ARCHIVE_OPT\";"
        
        # Log Filtering
        SMB_LOG_TMP="$TEMP_DIR/smb_upload.log"
        smbclient "//${SMB_HOST}/${SMB_SHARE}" -U "${SMB_USER}%${SMB_PASS}" -c "$FULL_CMDS" > "$SMB_LOG_TMP" 2>&1
        SMB_EXIT_CODE=$?
        grep -vE "$LOG_FILTER" "$SMB_LOG_TMP" >> "$LOG_FILE"
        
        if [ $SMB_EXIT_CODE -eq 0 ]; then
            logger_msg "Backup completed successfully." "INFO"
            
            if [ "$AUTO_PURGE" == "true" ]; then
                if [ ! -z "$RETENTION_DAYS" ] && [ "$RETENTION_DAYS" -gt 0 ]; then
                    run_retention_check "AUTO"
                fi
            else
                logger_msg "Auto-Purge skipped (Disabled)." "INFO"
            fi
        else
            logger_msg "SMB Upload Failed (Exit Code: $SMB_EXIT_CODE)." "ERROR"
        fi
    else
        ERR=$(cat /tmp/tar_err)
        logger_msg "Error creating OPT archive: $ERR" "ERROR"
    fi
    
    perform_cleanup
}

run_retention_check() {
    MODE=$1 # "AUTO" or empty (Manual)

    if [ -z "$RETENTION_DAYS" ] || [ "$RETENTION_DAYS" -le 0 ]; then
        echo -e "${CYellow}Retention policy is 0 or unset. Nothing to purge.${CClear}"
        return
    fi
    
    if [ "$MODE" != "AUTO" ]; then
        echo -e "${CBlue}Scanning for folders older than ${CWhite}$RETENTION_DAYS days${CBlue}...${CClear}"
    fi
    logger_msg "Starting Purge Check (Limit: $RETENTION_DAYS days)..." "INFO"
    
    PATH_CMDS=""
    CLEAN_PATH=$(echo "$SMB_SUBDIR" | sed 's/\// /g')
    for folder in $CLEAN_PATH; do
         [ ! -z "$folder" ] && [ "$folder" != "." ] && PATH_CMDS="$PATH_CMDS cd \"$folder\";"
    done
    
    CMDS="$PATH_CMDS ls"
    LIST=$(smbclient "//${SMB_HOST}/${SMB_SHARE}" -U "${SMB_USER}%${SMB_PASS}" -c "$CMDS" 2>/dev/null)
    CUTOFF_TS=$(date -d "-$RETENTION_DAYS days" +%s)
    
    echo "$LIST" | while read -r LINE; do
        if echo "$LINE" | grep -q " D "; then
             DIRNAME=$(echo "$LINE" | awk '{print $1}')
             if echo "$DIRNAME" | grep -qE '^[0-9]{8}_[0-9]{6}$'; then
                 
                 # FIX DATA PARSING
                 RAW_DATE=$(echo "$DIRNAME" | cut -d'_' -f1)
                 FMT_DATE="${RAW_DATE:0:4}-${RAW_DATE:4:2}-${RAW_DATE:6:2}"
                 DIR_TS=$(date -d "$FMT_DATE" +%s 2>/dev/null)
                 
                 if [ ! -z "$DIR_TS" ] && [ "$DIR_TS" -lt "$CUTOFF_TS" ]; then
                      
                      DO_DELETE="false"

                      if [ "$MODE" != "AUTO" ]; then
                          echo -e "${CYellow}Found OLD backup: ${CWhite}$DIRNAME${CYellow}${CClear}"
                          read -p "Delete this folder? (y/n): " CONFIRM_SINGLE < /dev/tty
                          if [ "$CONFIRM_SINGLE" == "y" ] || [ "$CONFIRM_SINGLE" == "Y" ]; then
                              DO_DELETE="true"
                          else
                              echo -e "${CGreen}Skipped.${CClear}"
                          fi
                      else
                          DO_DELETE="true"
                      fi
                      
                      if [ "$DO_DELETE" == "true" ]; then
                          logger_msg "Purging old backup folder: $DIRNAME" "WARN"
                          echo -e "${CRed}[DELETE] Deleting $DIRNAME ...${CClear}"
                          DEL_CMD="$PATH_CMDS recurse ON; deltree \"$DIRNAME\""
                          smbclient "//${SMB_HOST}/${SMB_SHARE}" -U "${SMB_USER}%${SMB_PASS}" -c "$DEL_CMD" 2>&1 | grep -vE "$LOG_FILTER"
                      fi
                 fi
             fi
        fi
    done
    
    if [ "$MODE" != "AUTO" ]; then
        echo -e "${CGreen}Purge Check Completed.${CClear}"
    fi
}

# --- USER INTERFACE ---

header() {
    clear
    CRON_STATUS=$(get_cron_status)
    if [ "$CRON_STATUS" == "ACTIVE" ]; then
        CRON_MSG="${CGreen}ACTIVE${CClear}"
        [ -z "$CRON_LABEL" ] && CRON_LABEL="Active (Custom)"
        SCHED_MSG="$CRON_LABEL"
    else
        CRON_MSG="${CRed}INACTIVE${CClear}"
        SCHED_MSG="-"
    fi

    echo -e "${InvDkGray}${CWhite} KEENETIC SMB BACKUP TOOL v$VERSION                                   ${CClear}"
    
    if [ "$CONFIG_STATUS" == "OK" ]; then
        echo -e "Status    : ${CGreen}CONFIGURED${CClear}"
        echo -e "Target    : //${SMB_HOST}/${SMB_SHARE}/${SMB_SUBDIR}"
        
        if [ "$AUTO_PURGE" == "true" ]; then
             MSG_AUTO="${CGreen}ON${CClear}"
        else
             MSG_AUTO="${CRed}OFF${CClear}"
        fi
        echo -e "Purge     : ${CYellow}${RETENTION_DAYS} days${CClear} (Auto: ${MSG_AUTO})"
        echo -e "Scheduler : $CRON_MSG ($SCHED_MSG)"
    else
        echo -e "Status    : ${CRed}NOT CONFIGURED ($CONFIG_FILE missing)${CClear}"
    fi
    echo ""
}

setup_wizard() {
    header
    echo -e "${CGreen}--- CONFIGURATION WIZARD ---${CClear}"
    
    read -p "SMB Server IP: " IN_HOST
    [ ! -z "$IN_HOST" ] && SMB_HOST="$IN_HOST"
    
    echo -e "\n${CYellow}NOTE: Share Name ONLY (e.g. VARIE)${CClear}"
    read -p "Share Name: " IN_SHARE
    [ ! -z "$IN_SHARE" ] && SMB_SHARE="$IN_SHARE"

    echo -e "\n${CYellow}NOTE: Full Path (e.g. Backup_ROUTER/KN-1812_Backup)${CClear}"
    read -p "Path [Default: Backup_ROUTER]: " IN_SUB
    if [ ! -z "$IN_SUB" ]; then SMB_SUBDIR="$IN_SUB"; else SMB_SUBDIR="Backup_ROUTER"; fi
    
    echo ""
    read -p "SMB User: " IN_USER
    [ ! -z "$IN_USER" ] && SMB_USER="$IN_USER"
    
    read -s -p "SMB Password: " IN_PASS
    echo ""
    [ ! -z "$IN_PASS" ] && SMB_PASS="$IN_PASS"
    
    echo -e "\n${CYellow}Other Settings${CClear}"
    read -p "Source [Enter for /opt]: " IN_DIR
    if [ ! -z "$IN_DIR" ]; then SOURCE_DIR="$IN_DIR"; else SOURCE_DIR="/opt"; fi
    
    read -p "Retention Days (e.g. 90): " IN_RET
    [ ! -z "$IN_RET" ] && RETENTION_DAYS="$IN_RET"

    echo -e "\n${CYellow}Enable Auto-Purge after backup?${CClear}"
    read -p "Auto Purge (y/n) [Default: y]: " IN_AUTO
    if [ "$IN_AUTO" == "n" ] || [ "$IN_AUTO" == "N" ]; then
        AUTO_PURGE="false"
    else
        AUTO_PURGE="true"
    fi
    
    save_config
}

show_menu() {
    while true; do
        load_config
        header
        
        echo -e "${InvDkGray}${CWhite}-----------------------------------------------------------------------------${CClear}\n"
        echo " 1. Configure Wizard"
        echo " 2. Run Backup Now"
        if [ ! -z "$RETENTION_DAYS" ]; then
             echo " 3. Run Purge Only (Interactive)"
        else
             echo " 3. Run Purge Only (Not Configured)"
        fi
        echo " 4. Test Connection"
        echo " 5. View Log"
        echo " 6. Scheduler (Cron)"
        echo " e. Exit"
        echo ""
        read -p "Choose option: " CHOICE
        case "$CHOICE" in
            1) setup_wizard ;;
            2) perform_backup; read -p "Press Enter..." ;;
            3) run_retention_check; read -p "Press Enter..." ;;
            4) test_connection; read -p "Press Enter..." ;;
            5) tail -n 20 "$LOG_FILE"; read -p "Press Enter..." ;;
            6) scheduler_menu ;;
            e|E) clear; exit 0 ;;
        esac
    done
}

# --- MAIN EXECUTION ---
check_dependencies
load_config
check_and_fix_cron_user

if [ "$1" == "-run" ]; then
    if [ "$CONFIG_STATUS" != "OK" ]; then logger_msg "Missing configuration." "ERROR"; exit 1; fi
    perform_backup
    exit 0
fi

show_menu
