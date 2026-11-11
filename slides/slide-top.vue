<script setup>
import courseLogo from './assets/libratech-logo-transparent.png'
</script>

<template>
  <img
    class="libratech-watermark"
    :src="courseLogo"
    alt=""
    aria-hidden="true"
  />
</template>

<style scoped>
.libratech-watermark {
  position: absolute;
  top: 10px;
  left: 14px;
  width: 64px;
  height: auto;
  opacity: 0.55;
  pointer-events: none;
  user-select: none;
  z-index: 100;
}
</style>
