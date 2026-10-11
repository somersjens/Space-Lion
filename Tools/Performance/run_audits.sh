#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
perf_tmp=$(mktemp -d /tmp/space-lion-audits.XXXXXX)
trap 'rm -rf "$perf_tmp"' EXIT
core_sources=(Core/GameConfig.swift Core/MathTopic.swift Core/PracticeMode.swift Core/MathQuestion.swift Core/DecimalAnswer.swift Core/SeededGenerator.swift Core/QuestionGenerator.swift Core/RoundFactory.swift)
swiftc -O -module-cache-path "$perf_tmp/module-cache" "${core_sources[@]}" Tools/Performance/CoreAudit.swift -o "$perf_tmp/core-audit"
"$perf_tmp/core-audit"
python3 - "$perf_tmp/director.swift" <<'PY'
import sys
from pathlib import Path
source = Path('Tutorial.swift').read_text()
source = source[source.index('// MARK: - Steps'):source.index('// MARK: - Hand-overs between screens')]
start = source.index('/// The warm stroke drawn')
end = source.index('// MARK: - What a step changes', start)
Path(sys.argv[1]).write_text('import Foundation\n' + source[:start] + source[end:])
PY
swiftc -module-cache-path "$perf_tmp/module-cache" -parse-as-library Core/GameConfig.swift "$perf_tmp/director.swift" Tools/Performance/TutorialAudit.swift -o "$perf_tmp/tutorial-audit"
"$perf_tmp/tutorial-audit"
