import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("multiplatform") version "2.0.20"

    `maven-publish`
}

group = "dev.hunter"
version = "0.0.1"

repositories {
    mavenCentral()
}

kotlin {
    jvm()
    linuxX64()
    mingwX64()

    sourceSets {
        val desktopMain by getting

        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material)
            implementation(compose.ui)
            implementation(compose.components.resources)
            implementation(compose.components.uiToolingPreview)
            implementation(libs.androidx.lifecycle.viewmodel)
            implementation(libs.androidx.lifecycle.runtime.compose)
        }
        desktopMain.dependencies {
            implementation(compose.desktop.currentOs)
            implementation(libs.kotlinx.coroutines.swing)
        }
        val commonMain by getting {
            dependencies {
                //put your multiplatform dependencies here
                implementation(kotlin("stdlib"))
                implementation(kotlin("reflect"))
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
            }
        }
        val commonTest by getting {
            dependencies {

            }
        }
    }
}

tasks {

    register("listComponents") {
        doLast {
            println("Available components:")
            components.get().report()
        }
    }

    publish {
        publishing {
            repositories {
                maven {
                    // change to point to your repo, e.g. http://my.org/repo
                    name = "github"
                    url = uri("https://maven.pkg.github.com/hunterkuppusamy/Nerve")
                    credentials {
                        username = "hunterkuppusamy"
                        password = System.getenv("TOKEN") ?: System.getenv("GITHUB_TOKEN") ?: project.findProperty("NERVE_PUBLISHING_TOKEN").toString()
                    }
                }
            }
            publications {
                create<MavenPublication>("Nerve") {
                    pom {
                        name = "Nerve"
                        description = "An interpreted language made on Tuesday"
                        url = "https://github.com/hunterkuppusamy/Nerve"
                        developers {
                            developer {
                                id = "hunter"
                                name = "Hunter Kuppusamy"
                                email = "hunterkupp@gmail.com"
                            }
                        }
                    }
                    groupId = project.group.toString()
                    artifactId = project.name.lowercase()
                    version = project.version.toString()
                }
            }
        }
    }
}
