<script setup>
import cover1 from '../assets/module-01-basic-sql-cover-enterprise-blue.png'
import cover2 from '../assets/module-02-advanced-sql-cover-enterprise-blue.png' 
import cover3 from '../assets/module-03-performance-tuning-cover-enterprise-blue.png'
import cover4 from '../assets/module-04-security-cover-enterprise-blue.png'
import cover5 from '../assets/module-05-architecture-cover-enterprise-blue.png'
import cover6 from '../assets/module-06-configuration-cover-enterprise-blue.png'
import cover7 from '../assets/module-07-backup-recovery-cover-enterprise-blue.png'
import cover9 from '../assets/module-09-monitoring-cover-enterprise-blue.png'
import cover10 from '../assets/module-10-modern-features-cover-enterprise-blue.png'
const props = defineProps({ moduleId: Number })
const covers = {1: cover1, 2: cover2, 3: cover3, 4: cover4, 5: cover5, 6: cover6, 7: cover7, 9: cover9, 10: cover10}
</script>

<template>
 <div class="cover-art"><img :src="covers[props.moduleId]" alt="ภาพประกอบบทเรียนจากธีมหลักสูตร PostgreSQL" /></div>
</template>
