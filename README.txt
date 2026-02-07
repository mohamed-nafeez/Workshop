Linux Treasure Hunt — README
----------------------------

Files:
 - treasure_hunt.sh       # main interactive bash script (make executable)
 - levels.json            # human-editable level definitions (created by script if missing)
 - .treasure_data/        # save/results folder created by script
 - cluecards/             # (optional) exported by admin: contains printable clue cards
 - certificate_<player>.txt  # created on completion
 - results_<player>.json     # created on completion

Quick start:
  1. Make the script executable:
       chmod +x treasure_hunt.sh

  2. Run the script:
       ./treasure_hunt.sh

  3. Optional flags:
       ./treasure_hunt.sh --debug
       ./treasure_hunt.sh --admin      # will prompt for admin password (see below)
       ./treasure_hunt.sh --seed=42    # reserved for future randomizable levels (no effect now)

Player flow:
 - Enter a player name. If a save exists, you can load it.
 - The script creates a per-player sandbox directory: ./treasure_sandbox_<player>
 - Each level contains one or more micro-tasks. For each step you must type a single shell command.
 - The command is validated for safety and pattern correctness before being executed inside the sandbox.
 - You can use commands: hint, status, inventory, save, quit, help, sandbox
 - Hints cost coins. You start with 5 coins. Wrong attempts deduct 1 coin (if you have coins).
 - After finishing a level you earn coins and a token. Tokens are shown in inventory.

Admin mode:
 - Start with --admin:
     ./treasure_hunt.sh --admin
 - Admin password:
     * If ADMIN_PASS env var is set on host, the script will ask for that password.
     * Otherwise the script allows you to set a password for that run.
 - Admin commands (enter at a player prompt prefixed with admin:):
     admin:reveal N       # show expected task patterns for level N
     admin:skip N         # advance the current player to level N (saves state)
     admin:cluecards      # export printable clue cards to ./cluecards/

Security / limitations:
 - The script uses a whitelist to restrict which commands can be executed in the sandbox.
 - Forbidden constructs include ;, &&, ||, backticks, $(), and common networking tools.
 - The sandbox is not a container — instructors should run the script in a safe environment.
 - The script writes save files to .treasure_data/ and certificates/results to the working directory.

Customization:
 - Edit levels.json to change wording, rewards, tokens, hints, or to add new levels.
 - The script will not auto-parse complex JSON edits; keep the same 'levels' array shape if you change it.
 - Admins can export cluecards to get printable single-page clues for each level.

Notes for workshop hosts:
 - Encourage participants to type the commands exactly (the script validates patterns).
 - Use --admin to reveal expected patterns if a group is stuck.
 - To reset a player, remove the file .treasure_data/save_<player>.txt

Contact:
 - This script is intentionally compact and beginner-friendly. If you need a multi-user web or timed
   competition version, consider porting to Python for more robust JSON parsing and web capabilities. 
