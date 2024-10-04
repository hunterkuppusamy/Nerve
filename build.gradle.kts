import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm") version "2.0.20"
    id("java")
    id("io.github.goooler.shadow") version "8.1.2"
}

group = "dev.hunter"
version = "0.0.1"

repositories {
    mavenCentral()
}

dependencies {
    api(kotlin("reflect"))
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.3.9")

    testImplementation(kotlin("test"))
}

tasks {
    test {
        useJUnitPlatform()
    }
    compileJava {
        options.release = 21
        options.encoding = "UTF-8"
    }
    compileKotlin {
        compilerOptions.jvmTarget.set(JvmTarget.JVM_21)
    }

    shadowJar {
        archiveFileName = "Nerve-${project.version}.jar"
        // from(sourceSets.main.get().output)
        minimize {
            exclude("kotlin/")
            exclude(dependency("org.jetbrains.kotlin:kotlin-stdlib"))
            exclude(dependency("org.jetbrains.kotlin:kotlin-reflect"))
        }
        minimize()
    }

    assemble {
        dependsOn(shadowJar)
    }
}

kotlin {
    jvmToolchain(21)
}