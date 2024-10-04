import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm") version "2.0.20"
    id("java")
    id("io.github.goooler.shadow") version "8.1.2"
    id("maven-publish")
    `maven-publish`
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

sourceSets {
    val main by getting {
        kotlin.srcDir("src/main/kotlin")
        resources.srcDir("src/main/resources")
    }
    val test by getting {
        kotlin.srcDir("src/test/kotlin")
        resources.srcDir("src/test/resources")
    }
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

kotlin {
    jvmToolchain(21)
}