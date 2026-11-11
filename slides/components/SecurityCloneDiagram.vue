<script setup>
const props = defineProps({ kind: { type: String, required: true } })
const titles = {
  clone: 'สำเนาข้อมูลใน schema แยก เก็บผลการทดลองใน Lab',
  foreignKeys: 'Foreign keys และ identity sequences อยู่ใน schema ของตน',
  roles: 'Login รับสิทธิ์จาก group roles โดยแยก owner ออก',
  gates: 'Schema USAGE, object privilege และ RLS ตรวจคนละขอบเขต',
  identity: 'Identity INSERT และ direct nextval ใช้ sequence privileges ต่างกัน',
  rls: 'Login จริงจับคู่ลูกค้าผ่าน session_user และ private mapping',
  view: 'Security invoker view ใช้สิทธิ์และ RLS ของผู้เรียก',
  audit: 'Approver เปลี่ยน status และ trigger บันทึก session_user',
  defaults: 'Default privileges มีผลกับ object ใหม่ที่ role นั้นสร้าง',
}
const arrow = `url(#m4c-arrow-${props.kind})`
</script>

<template>
  <svg class="m4c-diagram" viewBox="0 0 1000 330" role="img"
    :aria-labelledby="`m4c-title-${kind}`">
    <title :id="`m4c-title-${kind}`">{{ titles[kind] }}</title>
    <defs>
      <marker :id="`m4c-arrow-${kind}`" viewBox="0 0 10 10" refX="9" refY="5"
        markerWidth="7" markerHeight="7" orient="auto">
        <path d="M0 0 L10 5 L0 10" fill="#2d9fe7" />
      </marker>
    </defs>

    <g v-if="kind === 'clone'">
      <rect class="zone" x="20" y="20" width="380" height="255" />
      <rect class="zone lab" x="600" y="20" width="380" height="255" />
      <text class="heading" x="210" y="62">claimsure</text>
      <text class="heading" x="790" y="62">lab_m4_clone_xx</text>
      <text x="210" y="111">customer / policy / claim</text>
      <text x="790" y="111">customer / policy / claim</text>
      <text x="210" y="156">ข้อมูลจากบท 1–3</text>
      <text x="790" y="156">สำเนาจาก snapshot เดียวกัน</text>
      <text class="accent" x="210" y="225">ต้นทางสำหรับบทถัดไป</text>
      <text class="accent" x="790" y="225">GRANT / RLS / UPDATE / audit</text>
      <path class="link" d="M415 130 H585" :marker-end="arrow" />
      <text class="small" x="500" y="106">copy ครั้งแรก</text>
      <text x="500" y="313">สำเนาเก็บการเปลี่ยนแปลงของ Lab ไว้จริง</text>
    </g>

    <g v-else-if="kind === 'foreignKeys'">
      <text class="heading" x="500" y="30">lab_m4_clone_xx</text>
      <g v-for="(table, index) in ['customer', 'policy', 'claim']" :key="table">
        <rect class="zone" :x="25 + index * 335" y="72" width="280" height="110" />
        <text class="heading" :x="165 + index * 335" y="117">{{ table }}</text>
        <text class="small" :x="165 + index * 335" y="153">{{ table }}_id</text>
        <rect class="zone lab" :x="25 + index * 335" y="229" width="280" height="62" />
        <text class="small" :x="165 + index * 335" y="266">identity sequence ของ Lab</text>
        <path class="link" :d="`M${165 + index * 335} 226 V185`" :marker-end="arrow" />
      </g>
      <path class="link" d="M355 125 H315" :marker-end="arrow" />
      <path class="link" d="M690 125 H650" :marker-end="arrow" />
      <text class="small" x="335" y="102">FK</text>
      <text class="small" x="670" y="102">FK</text>
      <text class="small" x="500" y="312">INSERT และ nextval ขยับเลขในสำเนา</text>
    </g>

    <g v-else-if="kind === 'roles'">
      <rect class="owner" x="20" y="8" width="960" height="54" />
      <text class="accent" x="500" y="42">m4c_owner_xx · NOLOGIN · เจ้าของ objects · app ไม่มี membership</text>
      <g v-for="(row, index) in [
        ['read_a / read_b', 'reader', 'SELECT'],
        ['create_a', 'writer', 'SELECT + INSERT'],
        ['approve_a', 'approver', 'SELECT + UPDATE(status)'],
        ['audit', 'auditor', 'SELECT audit'],
      ]" :key="row[0]">
        <rect class="zone" x="20" :y="80 + index * 58" width="250" height="46" />
        <template v-if="index === 0">
          <text class="login-pair" x="145" y="100">m4c_read_a_xx</text>
          <text class="login-pair" x="145" y="119">m4c_read_b_xx</text>
        </template>
        <text v-else class="small" x="145" :y="110 + index * 58">m4c_{{ row[0] }}_xx</text>
        <path class="link" :d="`M280 ${103 + index * 58} H355`" :marker-end="arrow" />
        <rect class="zone lab" x="365" :y="80 + index * 58" width="220" height="46" />
        <text class="small" x="475" :y="110 + index * 58">m4c_{{ row[1] }}_xx</text>
        <text class="small left" x="620" :y="110 + index * 58">{{ row[2] }}</text>
      </g>
      <text class="small" x="500" y="320">writer / approver สืบทอด SELECT จาก reader</text>
    </g>

    <g v-else-if="kind === 'gates'">
      <g v-for="(row, index) in [
        ['Schema USAGE', 'เข้าถึง namespace', 'lab_m4_clone_xx'],
        ['Object privilege', 'ทำ operation ที่อนุญาต', 'SELECT / INSERT / UPDATE'],
        ['Row policy', 'อ่านหรือเขียนแถวที่อนุญาต', 'USING / WITH CHECK'],
      ]" :key="row[0]">
        <rect class="zone" :x="15 + index * 340" y="40" width="290" height="198" />
        <text class="heading" :x="160 + index * 340" y="90">{{ row[0] }}</text>
        <text class="small" :x="160 + index * 340" y="143">{{ row[1] }}</text>
        <text class="small accent" :x="160 + index * 340" y="198">{{ row[2] }}</text>
      </g>
      <path class="link" d="M310 136 H345" :marker-end="arrow" />
      <path class="link" d="M650 136 H685" :marker-end="arrow" />
      <text x="500" y="300">RLS ใช้กับ operation ที่ผู้เรียกมี object privilege อยู่แล้ว</text>
    </g>

    <g v-else-if="kind === 'identity'">
      <text class="heading left" x="30" y="39">m4c_create_a_xx</text>
      <rect class="zone" x="30" y="70" width="410" height="84" />
      <text x="235" y="105">INSERT ผ่าน GENERATED AS IDENTITY</text>
      <text class="small" x="235" y="135">มี INSERT บนคอลัมน์ที่ระบุ</text>
      <rect class="zone" x="30" y="195" width="410" height="84" />
      <text x="235" y="232">SELECT nextval(...)</text>
      <text class="small" x="235" y="261">เรียก sequence โดยตรง</text>
      <path class="link" d="M450 112 H585" :marker-end="arrow" />
      <path class="link" d="M450 236 H585" :marker-end="arrow" />
      <rect class="zone lab" x="600" y="70" width="370" height="84" />
      <text class="accent" x="785" y="122">INSERT สำเร็จ</text>
      <rect class="zone lab" x="600" y="195" width="370" height="84" />
      <text class="accent" x="785" y="231">ต้องมี sequence USAGE</text>
      <text class="small" x="785" y="261">ก่อน GRANT ได้ 42501</text>
      <text class="small" x="500" y="321">ทั้งสองเส้นทางใช้ sequence ของ lab_m4_clone_xx</text>
    </g>

    <g v-else-if="kind === 'rls'">
      <rect class="zone" x="15" y="50" width="270" height="180" />
      <text class="heading" x="150" y="92">TCP / SCRAM Login</text>
      <text class="small" x="150" y="142">m4c_read_a_xx</text>
      <text class="accent" x="150" y="194">session_user</text>
      <rect class="zone" x="365" y="50" width="270" height="180" />
      <text class="heading" x="500" y="92">Private mapping</text>
      <text class="small" x="500" y="142">login_customer</text>
      <text class="accent" x="500" y="194">CUS-001 / policy IDs</text>
      <rect class="zone lab" x="715" y="50" width="270" height="180" />
      <text class="heading" x="850" y="92">Claim RLS</text>
      <text class="small" x="850" y="142">allowed_policy_ids()</text>
      <text class="accent" x="850" y="194">เคลมของ CUS-001</text>
      <path class="link" d="M295 143 H350" :marker-end="arrow" />
      <path class="link" d="M645 143 H700" :marker-end="arrow" />
      <text class="small" x="500" y="285">Function อ่าน mapping ด้วยสิทธิ์ owner และคืนเฉพาะ policy IDs ของ Login นั้น</text>
      <text class="small" x="500" y="318">SET app.customer_id เองไม่เปลี่ยน session_user</text>
    </g>

    <g v-else-if="kind === 'view'">
      <text class="heading" x="500" y="35">claim_detail_v · security_invoker = true</text>
      <rect class="zone" x="20" y="83" width="300" height="130" />
      <text x="170" y="126">Reader A</text>
      <text class="small" x="170" y="172">สิทธิ์ของผู้เรียก</text>
      <rect class="zone" x="375" y="83" width="250" height="130" />
      <text x="500" y="126">View JOIN</text>
      <text class="small" x="500" y="172">claim / policy / customer</text>
      <rect class="zone lab" x="680" y="83" width="300" height="130" />
      <text x="830" y="126">Claim SELECT + RLS</text>
      <text class="small" x="830" y="172">เฉพาะเคลมของ CUS-001</text>
      <path class="link" d="M330 147 H360" :marker-end="arrow" />
      <path class="link" d="M635 147 H665" :marker-end="arrow" />
      <text x="500" y="279">ผู้เรียกต้องมี SELECT ของ view และคอลัมน์ฐานที่ view ใช้</text>
      <text class="small" x="500" y="316">Policy ของ claim ยังจำกัดแถวระหว่างอ่านผ่าน view</text>
    </g>

    <g v-else-if="kind === 'audit'">
      <rect class="zone" x="15" y="55" width="280" height="170" />
      <text class="heading" x="155" y="98">Approver</text>
      <text class="small" x="155" y="150">UPDATE(status)</text>
      <text class="small" x="155" y="194">เคลมของ CUS-001</text>
      <rect class="zone" x="360" y="55" width="280" height="170" />
      <text class="heading" x="500" y="98">Audit trigger</text>
      <text class="small" x="500" y="150">SECURITY DEFINER</text>
      <text class="small" x="500" y="194">เขียน audit ด้วยสิทธิ์ owner</text>
      <rect class="zone lab" x="705" y="55" width="280" height="170" />
      <text class="heading" x="845" y="98">claim_audit</text>
      <text class="small" x="845" y="150">old / new status</text>
      <text class="small" x="845" y="194">session_user ของ Approver</text>
      <path class="link" d="M305 140 H345" :marker-end="arrow" />
      <path class="link" d="M650 140 H690" :marker-end="arrow" />
      <text x="500" y="286">Auditor อ่านหลักฐานได้ โดยไม่มีสิทธิ์ SELECT claim</text>
      <text class="small" x="500" y="320">Trigger บันทึกเฉพาะ OLD.status ที่ต่างจาก NEW.status</text>
    </g>

    <g v-else-if="kind === 'defaults'">
      <text class="heading" x="500" y="35">ผู้สร้าง object: m4c_owner_xx</text>
      <path class="link" d="M40 150 H955" :marker-end="arrow" />
      <path class="tick" d="M500 75 V247" />
      <text class="small" x="500" y="282">ALTER DEFAULT PRIVILEGES</text>
      <text class="small" x="500" y="316">GRANT SELECT ON TABLES TO reader</text>
      <rect class="zone" x="35" y="66" width="365" height="64" />
      <text x="217" y="105">note_before_default</text>
      <text class="accent" x="217" y="215">Reader ได้ 42501</text>
      <rect class="zone lab" x="600" y="66" width="365" height="64" />
      <text x="782" y="105">note_after_default</text>
      <text class="accent" x="782" y="215">Reader อ่านได้</text>
    </g>
  </svg>
</template>

<style scoped>
.m4c-diagram { display: block; width: 100%; height: 310px; margin: .5rem auto; }
text { font-family: 'Noto Sans Thai', sans-serif; font-size: 22px; fill: #18395f; text-anchor: middle; }
.heading { font-weight: 700; font-size: 25px; fill: #0b356b; }
.small { font-size: 20px; }
.login-pair { font-size: 18px; }
.left { text-anchor: start; }
.accent { font-weight: 650; fill: #15599a; }
.zone { fill: #f4faff; stroke: #78cffa; stroke-width: 2; rx: 8; }
.lab { fill: #eaf7ff; stroke: #2d9fe7; }
.owner { fill: #f0f4f8; stroke: #b9ccdc; stroke-width: 2; rx: 6; }
.link { fill: none; stroke: #2d9fe7; stroke-width: 3; }
.tick { fill: none; stroke: #0b356b; stroke-width: 2.5; }
</style>
