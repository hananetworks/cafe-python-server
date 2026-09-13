const fs = require('fs');
const path = require('path');

// GitHub Actions 워크플로우 등에서 생성되는 결과물 이름
const OUTPUT_FILE = 'manifest.json';

console.log(`🔍 Manifest(메타데이터) 생성 시작...`);

// 이제 복잡한 파일 해시 비교는 필요 없습니다. (HDiffPatch가 다 알아서 함)
// 단순히 버전 관리/디버깅 용도로 언제 빌드되었는지만 남깁니다.

const manifest = {
    buildSystem: "HDiffPatch-Binary-Strategy",
    generatedAt: new Date().toISOString(),
    description: "이 파일은 빌드 시점을 기록하기 위한 메타데이터입니다. 업데이트 로직에는 관여하지 않습니다."
};

fs.writeFileSync(OUTPUT_FILE, JSON.stringify(manifest, null, 2));
console.log(`✅ Manifest 생성 완료: ${OUTPUT_FILE}`);