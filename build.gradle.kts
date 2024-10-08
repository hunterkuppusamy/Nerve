import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.jetbrainsCompose)
    alias(libs.plugins.compose.compiler)
    `maven-publish`
}

group = "dev.hunter.nerve"
version = "0.0.1"

kotlin {
    jvm()
    // no reason for these really...
    // linuxX64()
    // mingwX64()

    repositories {
        mavenCentral()
        google()
    }

    sourceSets {
        commonMain {
            dependencies {
                implementation(libs.kotlin.reflect)
                implementation(compose.runtime)
                implementation(compose.material)
                implementation(compose.desktop.common)
                implementation(compose.ui)
                implementation(compose.uiUtil)
                implementation(compose.uiTooling)
                implementation(compose.foundation)
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        jvmMain {
            dependencies {
                implementation(compose.desktop.currentOs)
            }
        }

        linuxMain {
            dependencies {
                implementation(compose.desktop.currentOs)
            }
        }

        mingwMain {
            dependencies {
                implementation(compose.desktop.currentOs)
            }
        }
    }
}

compose.desktop {
    application {
        mainClass = "dev.hunter.nerve.MainKt"

        nativeDistributions {
            targetFormats(TargetFormat.Exe, TargetFormat.AppImage, TargetFormat.Rpm)
            packageName = "dev.hunter.nerve"
            packageVersion = "0.0.1"
            includeAllModules = true
        }
    }
}

tasks {
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

                    from(getComponents()["kotlin"]) // the property delegate for the function is actually overloaded and idk how to not do that!
                }
            }
        }
    }
}
